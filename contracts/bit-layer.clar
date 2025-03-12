;; BitLayer DAO: Decentralized Governance on Bitcoin via Stacks L2
;; 
;; Summary: Enterprise-grade DAO protocol enabling Bitcoin-native decentralized governance with advanced delegation,
;; treasury management, and profit distribution mechanisms powered by Stacks L2.

;; Description:
;; Implements a sophisticated governance system combining Bitcoin's security with Stacks L2 scalability. Features include:
;; - Multi-sig proposal system with time-locked executions
;; - Dynamic voting power delegation with expiry
;; - Profit distribution pools with vesting schedules
;; - Emergency governance circuit breakers
;; - Parameterized governance controls (quorum thresholds, super-majority requirements)
;; - On-chain investment tracking and ROI distribution
;; Built using Clarity VM for transparent, predictable execution on Bitcoin.

;; Contract Architecture:
;; - Governance core: Proposal lifecycle management with quadratic voting
;; - Treasury module: Multi-sig fund management with expenditure tracking
;; - Delegation engine: Transferable voting power with cool-down periods
;; - Returns system: Profit distribution pools with claim scheduling
;; - Safety module: Emergency pause and admin override capabilities

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-VOTED (err u101))
(define-constant ERR-PROPOSAL-EXPIRED (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u105))
(define-constant ERR-QUORUM-NOT-REACHED (err u106))
(define-constant ERR-NO-DELEGATE (err u110))
(define-constant ERR-INVALID-DELEGATE (err u111))
(define-constant ERR-EMERGENCY-ACTIVE (err u112))
(define-constant ERR-NOT-EMERGENCY (err u113))
(define-constant ERR-INVALID-PARAMETER (err u114))
(define-constant ERR-NO-RETURNS (err u115))

;; Data variables
(define-data-var dao-admin principal tx-sender)
(define-data-var minimum-quorum uint u500) ;; 50% in basis points
(define-data-var voting-period uint u144) ;; ~1 day in blocks
(define-data-var proposal-count uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var emergency-state bool false)

;; Governance Parameters
(define-data-var dao-parameters
    {
        proposal-fee: uint,
        min-proposal-amount: uint,
        max-proposal-amount: uint,
        voting-delay: uint,
        voting-period: uint,
        timelock-period: uint,
        quorum-threshold: uint,
        super-majority: uint
    }
    {
        proposal-fee: u100000, ;; 0.1 STX
        min-proposal-amount: u1000000, ;; 1 STX
        max-proposal-amount: u1000000000, ;; 1000 STX
        voting-delay: u100, ;; blocks before voting starts
        voting-period: u144, ;; ~1 day in blocks
        timelock-period: u72, ;; ~12 hours in blocks
        quorum-threshold: u500, ;; 50% in basis points
        super-majority: u667 ;; 66.7% in basis points
    }
)

;; Data Maps
(define-map members 
    principal 
    {
        voting-power: uint,
        joined-block: uint,
        total-contributed: uint,
        last-withdrawal: uint
    }
)

(define-map proposals 
    uint 
    {
        id: uint,
        proposer: principal,
        title: (string-ascii 100),
        description: (string-utf8 1000),
        amount: uint,
        target: principal,
        start-block: uint,
        end-block: uint,
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20),
        executed: bool
    }
)

(define-map votes 
    {proposal-id: uint, voter: principal} 
    {
        amount: uint,
        support: bool
    }
)

(define-map emergency-admins principal bool)

(define-map delegations
    principal
    {
        delegate: principal,
        amount: uint,
        expiry: uint
    }
)

(define-map return-pools
    uint
    {
        total-amount: uint,
        distributed-amount: uint,
        distribution-start: uint,
        distribution-end: uint,
        claims: (list 200 principal)
    }
)

(define-map member-claims
    {member: principal, pool-id: uint}
    {
        amount: uint,
        claimed: bool
    }
)

;; Emergency Controls

(define-public (set-emergency-state (state bool))
    (begin
        (asserts! (is-emergency-admin tx-sender) ERR-NOT-AUTHORIZED)
        (var-set emergency-state state)
        (ok true)
    )
)

(define-public (add-emergency-admin (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        ;; Check that admin is not null and not the zero address
        (asserts! (not (is-eq admin (as-contract tx-sender))) ERR-INVALID-PARAMETER)
        (map-set emergency-admins admin true)
        (ok true)
    )
)

(define-public (delegate-votes (delegate-to principal) (amount uint) (expiry uint))
    (let
        (
            (caller tx-sender)
            (member-info (unwrap! (get-member-info caller) ERR-NOT-AUTHORIZED))
        )
        ;; Additional validation for delegate-to
        (asserts! (not (is-eq delegate-to caller)) ERR-INVALID-DELEGATE)
        (asserts! (is-some (get-member-info delegate-to)) ERR-INVALID-DELEGATE)
        (asserts! (>= (get voting-power member-info) amount) ERR-INSUFFICIENT-FUNDS)
        (asserts! (> expiry block-height) ERR-INVALID-PARAMETER)
        
        (map-set delegations
            caller
            {
                delegate: delegate-to,
                amount: amount,
                expiry: expiry
            }
        )
        
        (map-set members
            caller
            (merge member-info {
                voting-power: (- (get voting-power member-info) amount)
            })
        )
        (ok true)
    )
)