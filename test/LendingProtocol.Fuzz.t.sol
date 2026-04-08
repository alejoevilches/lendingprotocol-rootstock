// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/LendingProtocol.sol";

contract LendingProtocolFuzzTest is Test {
    LendingProtocol public lendingProtocol;

    address public admin;
    address public borrower;
    address public lenderA;
    address public lenderB;

    uint256 constant LOAN_AMOUNT = 10 ether;
    uint256 constant INTEREST_A = 500; // 5%

    function setUp() public {
        lendingProtocol = new LendingProtocol();

        admin = address(this);
        borrower = makeAddr("borrower");
        lenderA = makeAddr("lenderA");
        lenderB = makeAddr("lenderB");

        vm.deal(borrower, 10000 ether);
        vm.deal(lenderA, 10000 ether);
        vm.deal(lenderB, 10000 ether);
    }

    function _createLoanAs(address actor, uint256 amount) internal returns (uint256) {
        vm.prank(actor);
        lendingProtocol.createLoan(amount);
        return lendingProtocol.loanCounter() - 1;
    }

    function _startBiddingAs(address actor, uint256 loanId) internal {
        vm.prank(actor);
        lendingProtocol.startBiddingProcess(loanId);
    }

    function _bidAs(address actor, uint256 loanId, uint256 interest, uint256 principal) internal returns (uint256) {
        vm.prank(actor);
        lendingProtocol.bidLoan{value: principal}(loanId, interest);
        return lendingProtocol.bidCounter() - 1;
    }

    function _repaymentAmount(uint256 principal, uint256 interestBps) internal pure returns (uint256) {
        return principal + (principal * interestBps / 10000);
    }

    function testFuzz_CreateLoan_StoresAnyNonZeroAmount(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 ether);

        vm.prank(borrower);
        lendingProtocol.createLoan(amount);

        assertEq(lendingProtocol.loanCounter(), 1);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(0);
        assertEq(loan.amount, amount);
        assertEq(loan.owner, borrower);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.REQUESTED));
    }

    function testFuzz_BidLoan_AcceptsAnyInterestInRange(uint256 interest) public {
        interest = bound(interest, 1, 10000);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);

        _bidAs(lenderA, loanId, interest, LOAN_AMOUNT);

        assertEq(lendingProtocol.bidCounter(), 1);

        ILendingProtocol.Bid memory bid = lendingProtocol.getBid(0);
        assertEq(bid.interest, interest);
        assertEq(bid.principal, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, 0);
        assertTrue(loan.hasBestBid);
    }

    function testFuzz_BidLoan_RevertsForInvalidInterest(uint256 interest) public {
        vm.assume(interest == 0 || interest > 10000);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_InvalidInterestRate.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, interest);
    }

    function testFuzz_BidLoan_RevertsWhenPrincipalDiffers(uint256 principal) public {
        principal = bound(principal, 0, 100 ether);
        vm.assume(principal != LOAN_AMOUNT);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_InvalidPrincipalAmount.selector);
        lendingProtocol.bidLoan{value: principal}(loanId, INTEREST_A);
    }

    function testFuzz_BidLoan_LowerInterestBecomesBest(uint256 firstInterest, uint256 secondInterest) public {
        firstInterest = bound(firstInterest, 2, 10000);
        secondInterest = bound(secondInterest, 1, firstInterest - 1);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);

        _bidAs(lenderA, loanId, firstInterest, LOAN_AMOUNT);
        uint256 secondBidId = _bidAs(lenderB, loanId, secondInterest, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, secondBidId);
    }

    function testFuzz_BidLoan_TiedInterestKeepsFirstBid(uint256 interest) public {
        interest = bound(interest, 1, 10000);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);

        uint256 firstBidId = _bidAs(lenderA, loanId, interest, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, interest, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, firstBidId);
    }

    function testFuzz_PayLoan_ComputesRepaymentCorrectly(uint256 amount, uint256 interest) public {
        amount = bound(amount, 1 ether, 100 ether);
        interest = bound(interest, 1, 10000);

        uint256 loanId = _createLoanAs(borrower, amount);
        _startBiddingAs(borrower, loanId);
        _bidAs(lenderA, loanId, interest, amount);

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        uint256 lenderBalanceBefore = lenderA.balance;
        uint256 repayment = _repaymentAmount(amount, interest);

        vm.prank(borrower);
        lendingProtocol.payLoan{value: repayment}(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.PAYED));
        assertEq(lenderA.balance, lenderBalanceBefore + repayment);
    }

    function testFuzz_PayLoan_RefundsExcess(uint256 amount, uint256 interest, uint256 extra) public {
        amount = bound(amount, 1 ether, 100 ether);
        interest = bound(interest, 1, 10000);
        extra = bound(extra, 1 wei, 10 ether);

        uint256 loanId = _createLoanAs(borrower, amount);
        _startBiddingAs(borrower, loanId);
        _bidAs(lenderA, loanId, interest, amount);

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        uint256 borrowerBalanceBefore = borrower.balance;
        uint256 repayment = _repaymentAmount(amount, interest);

        vm.prank(borrower);
        lendingProtocol.payLoan{value: repayment + extra}(loanId);

        assertEq(borrower.balance, borrowerBalanceBefore - repayment);
    }

    function testFuzz_DefaultLoan_SucceedsAfterDueDate(uint256 warpOffset) public {
        warpOffset = bound(warpOffset, 31 days, 365 days);

        uint256 loanId = _createLoanAs(borrower, LOAN_AMOUNT);
        _startBiddingAs(borrower, loanId);
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        ILendingProtocol.Loan memory loanBefore = lendingProtocol.getLoan(loanId);
        vm.warp(loanBefore.dueDate + warpOffset);

        lendingProtocol.defaultLoan(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.DEFAULTED));
    }
}