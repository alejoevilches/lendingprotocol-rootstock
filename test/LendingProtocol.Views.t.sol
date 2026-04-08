// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/LendingProtocol.sol";
import "interfaces/ILendingProtocol.sol";

contract LendingProtocolViewsTest is Test {
    LendingProtocol public lendingProtocol;

    address public admin;
    address public borrower;
    address public lenderA;
    address public lenderB;

    uint256 constant LOAN_AMOUNT = 10 ether;
    uint256 constant INTEREST_A = 500; // 5%
    uint256 constant INTEREST_B = 800; // 8%

    function setUp() public {
        lendingProtocol = new LendingProtocol();

        admin = address(this);
        borrower = makeAddr("borrower");
        lenderA = makeAddr("lenderA");
        lenderB = makeAddr("lenderB");

        vm.deal(borrower, 100 ether);
        vm.deal(lenderA, 100 ether);
        vm.deal(lenderB, 100 ether);
    }

    function _createRequestedLoan() internal returns (uint256) {
        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);
        return lendingProtocol.loanCounter() - 1;
    }

    function _createBiddingLoan() internal returns (uint256) {
        uint256 loanId = _createRequestedLoan();
        vm.prank(borrower);
        lendingProtocol.startBiddingProcess(loanId);
        return loanId;
    }

    function _createClosedLoanOneBid() internal returns (uint256) {
        uint256 loanId = _createBiddingLoan();
        vm.prank(lenderA);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);
        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);
        return loanId;
    }

    function _repaymentAmount(uint256 principal, uint256 interestBps) internal pure returns (uint256) {
        return principal + (principal * interestBps / 10000);
    }

    function _warpToAfterDueDate(uint256 loanId) internal {
        ILendingProtocol.LoanView memory loanView = lendingProtocol.getLoanView(loanId);
        vm.warp(loanView.loan.dueDate + 1);
    }

    function test_GetLoanView_ReturnsCorrectDataForRequestedLoan() public {
        uint256 loanId = _createRequestedLoan();

        ILendingProtocol.LoanView memory loanView = lendingProtocol.getLoanView(loanId);

        assertEq(loanView.loan.id, loanId);
        assertEq(loanView.loan.owner, borrower);
        assertEq(loanView.loan.amount, LOAN_AMOUNT);
        assertEq(loanView.winningBidId, 0);
        assertEq(loanView.repaymentAmount, 0);
        assertFalse(loanView.canRepay);
        assertFalse(loanView.canDefault);
    }

    function test_GetLoanView_ReturnsCanRepayWhenLoanIsClosedAndNotExpired() public {
        uint256 loanId = _createClosedLoanOneBid();

        ILendingProtocol.LoanView memory loanView = lendingProtocol.getLoanView(loanId);

        assertEq(loanView.winningBidId, 0);
        assertEq(loanView.repaymentAmount, _repaymentAmount(LOAN_AMOUNT, INTEREST_A));
        assertTrue(loanView.canRepay);
        assertFalse(loanView.canDefault);
    }

    function test_GetLoanView_ReturnsCanDefaultWhenLoanIsClosedAndExpired() public {
        uint256 loanId = _createClosedLoanOneBid();
        _warpToAfterDueDate(loanId);

        ILendingProtocol.LoanView memory loanView = lendingProtocol.getLoanView(loanId);

        assertTrue(loanView.canDefault);
        assertFalse(loanView.canRepay);
    }

    function test_GetLoanView_RevertsWhenLoanIdInvalid() public {
        vm.expectRevert(LendingProtocol.InvalidLoanId.selector);
        lendingProtocol.getLoanView(999);
    }

    function test_GetLoanViews_ReturnsPaginatedLoans() public {
        _createRequestedLoan();
        _createRequestedLoan();
        _createRequestedLoan();

        ILendingProtocol.LoanView[] memory views = lendingProtocol.getLoanViews(0, 2);

        assertEq(views.length, 2);
        assertEq(views[0].loan.id, 0);
        assertEq(views[1].loan.id, 1);
    }

    function test_GetLoanViews_ReturnsEmptyWhenOffsetExceedsTotal() public {
        _createRequestedLoan();

        ILendingProtocol.LoanView[] memory views = lendingProtocol.getLoanViews(10, 5);

        assertEq(views.length, 0);
    }

    function test_GetLoanViews_ReturnsRemainingWhenLimitExceedsTotal() public {
        _createRequestedLoan();
        _createRequestedLoan();

        ILendingProtocol.LoanView[] memory views = lendingProtocol.getLoanViews(0, 10);

        assertEq(views.length, 2);
    }
}