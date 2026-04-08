// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/LendingProtocol.sol";
import "interfaces/ILendingProtocol.sol";
import "test/mocks/RejectEtherReceiver.sol";

contract LendingProtocolTest is Test {
    LendingProtocol public lendingProtocol;

    address public admin;
    address public borrower;
    address public lenderA;
    address public lenderB;
    address public outsider;

    uint256 constant LOAN_AMOUNT = 10 ether;
    uint256 constant INTEREST_A = 500; // 5%
    uint256 constant INTEREST_B = 800; // 8%

    function setUp() public {
        lendingProtocol = new LendingProtocol();

        admin = address(this);
        borrower = makeAddr("borrower");
        lenderA = makeAddr("lenderA");
        lenderB = makeAddr("lenderB");
        outsider = makeAddr("outsider");

        vm.deal(borrower, 100 ether);
        vm.deal(lenderA, 100 ether);
        vm.deal(lenderB, 100 ether);
        vm.deal(outsider, 100 ether);
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

    function _createRequestedLoan() internal returns (uint256) {
        return _createLoanAs(borrower, LOAN_AMOUNT);
    }

    function _createBiddingLoan() internal returns (uint256) {
        uint256 loanId = _createRequestedLoan();
        _startBiddingAs(borrower, loanId);
        return loanId;
    }

    function _createClosedLoanOneBid() internal returns (uint256) {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);
        return loanId;
    }

    function _createClosedLoanTwoBids() internal returns (uint256) {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);
        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);
        return loanId;
    }

    function _repaymentAmount(uint256 principal, uint256 interestBps) internal pure returns (uint256) {
        return principal + (principal * interestBps / 10000);
    }

    function _warpToAfterDueDate(uint256 loanId) internal {
        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        vm.warp(loan.dueDate + 1);
    }

    function test_Constructor_SetsAdmin() public {
        assertEq(lendingProtocol.ADMIN(), admin);
    }

    function test_Constructor_InitialCountersAreZero() public {
        assertEq(lendingProtocol.loanCounter(), 0);
        assertEq(lendingProtocol.bidCounter(), 0);
    }

    function test_CreateLoan_Succeeds() public {
        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);

        assertEq(lendingProtocol.loanCounter(), 1);
    }

    function test_CreateLoan_StoresCorrectLoanData() public {
        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(0);

        assertEq(loan.id, 0);
        assertEq(loan.owner, borrower);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.REQUESTED));
        assertEq(loan.amount, LOAN_AMOUNT);
    }

    function test_CreateLoan_IncrementsLoanCounter() public {
        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);

        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);

        assertEq(lendingProtocol.loanCounter(), 2);
    }

    function test_CreateLoan_EmitsLoanCreated() public {
        vm.prank(borrower);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanCreated(0, borrower, LOAN_AMOUNT);
        lendingProtocol.createLoan(LOAN_AMOUNT);
    }

    function test_CreateLoan_RevertWhenAmountIsZero() public {
        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.CreateLoan_ZeroAmount.selector);
        lendingProtocol.createLoan(0);
    }

    function test_StartBidding_ByOwner_Succeeds() public {
        uint256 loanId = _createRequestedLoan();

        vm.prank(borrower);
        lendingProtocol.startBiddingProcess(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.BIDDING));
    }

    function test_StartBidding_ByAdmin_Succeeds() public {
        uint256 loanId = _createRequestedLoan();

        lendingProtocol.startBiddingProcess(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.BIDDING));
    }

    function test_StartBidding_EmitsBiddingStarted() public {
        uint256 loanId = _createRequestedLoan();

        vm.prank(borrower);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.BiddingStarted(loanId);
        lendingProtocol.startBiddingProcess(loanId);
    }

    function test_StartBidding_RevertWhenCallerIsNotOwnerOrAdmin() public {
        uint256 loanId = _createRequestedLoan();

        vm.prank(outsider);
        vm.expectRevert(LendingProtocol.OnlyLoanOwner_NotOwner.selector);
        lendingProtocol.startBiddingProcess(loanId);
    }

    function test_StartBidding_RevertWhenLoanIdInvalid() public {
        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.InvalidLoanId.selector);
        lendingProtocol.startBiddingProcess(999);
    }

    function test_StartBidding_RevertWhenLoanIsNotRequested() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.StartBiddingProcess_InvalidStateOfLoan.selector);
        lendingProtocol.startBiddingProcess(loanId);
    }

    function test_BidLoan_Succeeds() public {
        uint256 loanId = _createBiddingLoan();
        uint256 bidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        ILendingProtocol.Bid memory bid = lendingProtocol.getBid(bidId);
        assertEq(bid.bidder, lenderA);
        assertEq(bid.interest, INTEREST_A);
        assertEq(bid.principal, LOAN_AMOUNT);
    }

    function test_BidLoan_IncrementsBidCounter() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        assertEq(lendingProtocol.bidCounter(), 1);

        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);
        assertEq(lendingProtocol.bidCounter(), 2);
    }

    function test_BidLoan_AppendsBidIdToLoan() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);

        uint256[] memory bidIds = lendingProtocol.getLoanBidIds(loanId);
        assertEq(bidIds.length, 2);
    }

    function test_BidLoan_SetsBestBidOnFirstBid() public {
        uint256 loanId = _createBiddingLoan();
        uint256 bidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, bidId);
        assertTrue(loan.hasBestBid);
    }

    function test_BidLoan_UpdatesBestBidWhenLowerInterestArrives() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);
        uint256 betterBidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, betterBidId);
    }

    function test_BidLoan_KeepsBestBidWhenHigherInterestArrives() public {
        uint256 loanId = _createBiddingLoan();

        uint256 firstBidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, firstBidId);
    }

    function test_BidLoan_KeepsFirstBestBidOnTie() public {
        uint256 loanId = _createBiddingLoan();

        uint256 firstBidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, INTEREST_A, LOAN_AMOUNT);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.bestBidId, firstBidId);
    }

    function test_BidLoan_EmitsBidPlaced() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(lenderA);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.BidPlaced(loanId, 0, lenderA, INTEREST_A);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);
    }

    function test_BidLoan_RevertWhenLoanIdInvalid() public {
        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.InvalidLoanId.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(999, INTEREST_A);
    }

    function test_BidLoan_RevertWhenLoanNotInBiddingStatus() public {
        uint256 loanId = _createRequestedLoan();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_LoanNotInBiddingStatus.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);
    }

    function test_BidLoan_RevertWhenInterestIsZero() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_InvalidInterestRate.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, 0);
    }

    function test_BidLoan_RevertWhenInterestExceedsMax() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_InvalidInterestRate.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, 10001);
    }

    function test_BidLoan_RevertWhenOwnerBids() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.BidLoan_OwnerCannotBid.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);
    }

    function test_BidLoan_RevertWhenBidderAlreadyBidOnLoan() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_DuplicateBidder.selector);
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_B);
    }

    function test_BidLoan_RevertWhenPrincipalDoesNotMatchLoanAmount() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.BidLoan_InvalidPrincipalAmount.selector);
        lendingProtocol.bidLoan{value: 5 ether}(loanId, INTEREST_A);
    }

    function test_CloseLoan_ByOwner_Succeeds() public {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        uint256 borrowerBalanceBefore = borrower.balance;

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.CLOSED));
        assertEq(loan.lender, lenderA);
        assertTrue(loan.startDate > 0);
        assertTrue(loan.dueDate > loan.startDate);
        assertEq(borrower.balance, borrowerBalanceBefore + LOAN_AMOUNT);
    }

    function test_CloseLoan_ByAdmin_Succeeds() public {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        lendingProtocol.closeLoan(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.CLOSED));
    }

    function test_CloseLoan_SetsWinningBidId() public {
        uint256 loanId = _createBiddingLoan();
        uint256 bidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        assertEq(lendingProtocol.getWinningBidId(loanId), bidId);
    }

    function test_CloseLoan_EmitsLoanClosed() public {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(borrower);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanClosed(loanId, 0, lenderA);
        lendingProtocol.closeLoan(loanId);
    }

    function test_CloseLoan_RevertWhenCallerIsNotOwnerOrAdmin() public {
        uint256 loanId = _createBiddingLoan();
        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(outsider);
        vm.expectRevert(LendingProtocol.OnlyLoanOwner_NotOwner.selector);
        lendingProtocol.closeLoan(loanId);
    }

    function test_CloseLoan_RevertWhenLoanNotInBiddingStatus() public {
        uint256 loanId = _createRequestedLoan();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.CloseLoan_InvalidStateOfLoan.selector);
        lendingProtocol.closeLoan(loanId);
    }

    function test_CloseLoan_RevertWhenLoanHasNoBids() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.CloseLoan_LoanHasNoBids.selector);
        lendingProtocol.closeLoan(loanId);
    }

    function test_PayLoan_SucceedsWithExactAmount() public {
        uint256 loanId = _createClosedLoanOneBid();

        uint256 lenderBalanceBefore = lenderA.balance;
        uint256 repayment = _repaymentAmount(LOAN_AMOUNT, INTEREST_A);

        vm.prank(borrower);
        lendingProtocol.payLoan{value: repayment}(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.PAYED));
        assertEq(lenderA.balance, lenderBalanceBefore + repayment);
    }

    function test_PayLoan_SucceedsWithExcessAndRefundsDifference() public {
        uint256 loanId = _createClosedLoanOneBid();

        uint256 borrowerBalanceBefore = borrower.balance;
        uint256 repayment = _repaymentAmount(LOAN_AMOUNT, INTEREST_A);
        uint256 excess = 2 ether;

        vm.prank(borrower);
        lendingProtocol.payLoan{value: repayment + excess}(loanId);

        assertEq(borrower.balance, borrowerBalanceBefore - repayment);
    }

    function test_PayLoan_EmitsLoanPayed() public {
        uint256 loanId = _createClosedLoanOneBid();
        uint256 repayment = _repaymentAmount(LOAN_AMOUNT, INTEREST_A);

        vm.prank(borrower);
        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanPayed(loanId, repayment);
        lendingProtocol.payLoan{value: repayment}(loanId);
    }

    function test_PayLoan_RevertWhenCallerIsNotLoanOwner() public {
        uint256 loanId = _createClosedLoanOneBid();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.OnlyLoanOwner_NotOwner.selector);
        lendingProtocol.payLoan{value: LOAN_AMOUNT}(loanId);
    }

    function test_PayLoan_RevertWhenLoanNotClosed() public {
        uint256 loanId = _createBiddingLoan();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.PayLoan_InvalidState.selector);
        lendingProtocol.payLoan{value: LOAN_AMOUNT}(loanId);
    }

    function test_PayLoan_RevertWhenPastDueDate() public {
        uint256 loanId = _createClosedLoanOneBid();
        _warpToAfterDueDate(loanId);

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.PayLoan_PastDueDate.selector);
        lendingProtocol.payLoan{value: _repaymentAmount(LOAN_AMOUNT, INTEREST_A)}(loanId);
    }

    function test_PayLoan_RevertWhenValueIsInsufficient() public {
        uint256 loanId = _createClosedLoanOneBid();

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.PayLoan_NotEnoughRBTC.selector);
        lendingProtocol.payLoan{value: 5 ether}(loanId);
    }

    function test_DefaultLoan_SucceedsAfterDueDate() public {
        uint256 loanId = _createClosedLoanOneBid();
        _warpToAfterDueDate(loanId);

        lendingProtocol.defaultLoan(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.DEFAULTED));
    }

    function test_DefaultLoan_EmitsLoanDefaulted() public {
        uint256 loanId = _createClosedLoanOneBid();
        _warpToAfterDueDate(loanId);

        vm.expectEmit(true, true, true, true);
        emit ILendingProtocol.LoanDefaulted(loanId);
        lendingProtocol.defaultLoan(loanId);
    }

    function test_DefaultLoan_RevertWhenLoanNotClosed() public {
        uint256 loanId = _createBiddingLoan();

        vm.expectRevert(LendingProtocol.DefaultLoan_LoanNotInClosedStatus.selector);
        lendingProtocol.defaultLoan(loanId);
    }

    function test_DefaultLoan_RevertWhenCalledBeforeDueDate() public {
        uint256 loanId = _createClosedLoanOneBid();

        vm.expectRevert(LendingProtocol.DefaultLoan_LoanNotInClosedStatus.selector);
        lendingProtocol.defaultLoan(loanId);
    }

    function test_DefaultLoan_CanBeCalledByAnyone_CurrentBehavior() public {
        uint256 loanId = _createClosedLoanOneBid();
        _warpToAfterDueDate(loanId);

        vm.prank(outsider);
        lendingProtocol.defaultLoan(loanId);

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(uint256(loan.status), uint256(ILendingProtocol.LendingState.DEFAULTED));
    }

    function test_Withdraw_RevertWhenNoFunds() public {
        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.Withdraw_NoFunds.selector);
        lendingProtocol.withdraw();
    }

    function test_WithdrawBid_SucceedsForLosingBidder() public {
        uint256 loanId = _createClosedLoanTwoBids();

        uint256 lenderBBalanceBefore = lenderB.balance;
        uint256 bidId = 1; // lenderB's bid

        vm.prank(lenderB);
        lendingProtocol.withdrawBid(bidId);

        assertEq(lenderB.balance, lenderBBalanceBefore + LOAN_AMOUNT);
    }

    function test_WithdrawBid_MarksBidAsWithdrawn() public {
        uint256 loanId = _createClosedLoanTwoBids();

        uint256 bidId = 1;

        vm.prank(lenderB);
        lendingProtocol.withdrawBid(bidId);

        ILendingProtocol.Bid memory bid = lendingProtocol.getBid(bidId);
        assertTrue(bid.withdrawn);
    }

    function test_WithdrawBid_RevertWhenBidIdInvalid() public {
        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.InvalidBidId.selector);
        lendingProtocol.withdrawBid(999);
    }

    function test_WithdrawBid_RevertWhenCallerIsNotBidder() public {
        uint256 loanId = _createClosedLoanTwoBids();

        vm.prank(outsider);
        vm.expectRevert(LendingProtocol.WithdrawBid_NotYourBid.selector);
        lendingProtocol.withdrawBid(0);
    }

    function test_WithdrawBid_RevertWhenAlreadyWithdrawn() public {
        uint256 loanId = _createClosedLoanTwoBids();

        vm.prank(lenderB);
        lendingProtocol.withdrawBid(1);

        vm.prank(lenderB);
        vm.expectRevert(LendingProtocol.WithdrawBid_AlreadyWithdrawn.selector);
        lendingProtocol.withdrawBid(1);
    }

    function test_WithdrawBid_WinningBidZeroCanWithdraw_CurrentBug() public {
        uint256 loanId = _createClosedLoanOneBid();

        vm.prank(lenderA);
        vm.expectRevert(LendingProtocol.Withdraw_ErrorSendingRBTC.selector);
        lendingProtocol.withdrawBid(0);
    }

    function test_WithdrawBid_AllowsWithdrawalWhileLoanStillActive_CurrentBehavior() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);

        vm.prank(lenderB);
        lendingProtocol.withdrawBid(0);

        ILendingProtocol.Bid memory bid = lendingProtocol.getBid(0);
        assertTrue(bid.withdrawn);
    }

    function test_GetLoan_ReturnsStoredLoan() public {
        uint256 loanId = _createRequestedLoan();

        ILendingProtocol.Loan memory loan = lendingProtocol.getLoan(loanId);
        assertEq(loan.id, loanId);
    }

    function test_GetLoan_RevertWhenLoanIdInvalid() public {
        vm.expectRevert(LendingProtocol.InvalidLoanId.selector);
        lendingProtocol.getLoan(999);
    }

    function test_GetBid_ReturnsStoredBid() public {
        uint256 loanId = _createBiddingLoan();
        uint256 bidId = _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        ILendingProtocol.Bid memory bid = lendingProtocol.getBid(bidId);
        assertEq(bid.id, bidId);
    }

    function test_GetBid_RevertWhenBidIdInvalid() public {
        vm.expectRevert(LendingProtocol.InvalidBidId.selector);
        lendingProtocol.getBid(999);
    }

    function test_GetLoanBidIds_ReturnsAllBidIds() public {
        uint256 loanId = _createBiddingLoan();

        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);
        _bidAs(lenderB, loanId, INTEREST_B, LOAN_AMOUNT);

        uint256[] memory bidIds = lendingProtocol.getLoanBidIds(loanId);
        assertEq(bidIds.length, 2);
    }

    function test_GetWinningBidId_ReturnsWinningBidId() public {
        uint256 loanId = _createClosedLoanOneBid();

        assertEq(lendingProtocol.getWinningBidId(loanId), 0);
    }

    function test_GetPendingWithdrawal_ReturnsZeroByDefault() public {
        assertEq(lendingProtocol.getPendingWithdrawal(borrower), 0);
    }

    function test_CloseLoan_RevertWhenBorrowerRejectsEther() public {
        RejectEtherReceiver rejectReceiver = new RejectEtherReceiver();
        vm.deal(address(rejectReceiver), 100 ether);

        vm.prank(address(rejectReceiver));
        lendingProtocol.createLoan(LOAN_AMOUNT);
        uint256 loanId = 0;

        vm.prank(address(rejectReceiver));
        lendingProtocol.startBiddingProcess(loanId);

        _bidAs(lenderA, loanId, INTEREST_A, LOAN_AMOUNT);

        vm.prank(address(rejectReceiver));
        vm.expectRevert(LendingProtocol.CloseLoan_ErrorFundingBorrower.selector);
        lendingProtocol.closeLoan(loanId);
    }

    function test_PayLoan_RevertWhenPaymentToLenderFails() public {
        RejectEtherReceiver rejectReceiver = new RejectEtherReceiver();
        vm.deal(address(rejectReceiver), 100 ether);

        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);
        uint256 loanId = 0;

        vm.prank(borrower);
        lendingProtocol.startBiddingProcess(loanId);

        vm.deal(address(rejectReceiver), 100 ether);
        vm.prank(address(rejectReceiver));
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);

        vm.prank(borrower);
        lendingProtocol.closeLoan(loanId);

        uint256 repayment = _repaymentAmount(LOAN_AMOUNT, INTEREST_A);
        vm.deal(borrower, repayment);

        vm.prank(borrower);
        vm.expectRevert(LendingProtocol.PayLoan_ErrorPayingLoan.selector);
        lendingProtocol.payLoan{value: repayment}(loanId);
    }

    function test_WithdrawBid_RevertWhenReceiverRejectsEther() public {
        RejectEtherReceiver rejectReceiver = new RejectEtherReceiver();
        vm.deal(address(rejectReceiver), 100 ether);

        vm.prank(borrower);
        lendingProtocol.createLoan(LOAN_AMOUNT);
        uint256 loanId = 0;

        vm.prank(borrower);
        lendingProtocol.startBiddingProcess(loanId);

        vm.deal(address(rejectReceiver), 100 ether);
        vm.prank(address(rejectReceiver));
        lendingProtocol.bidLoan{value: LOAN_AMOUNT}(loanId, INTEREST_A);

        vm.prank(address(rejectReceiver));
        vm.expectRevert(LendingProtocol.Withdraw_ErrorSendingRBTC.selector);
        lendingProtocol.withdrawBid(0);
    }
}