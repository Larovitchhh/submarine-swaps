;; ------------------------------------------------------------
;; STX Submarine Swap (HTLC-style)
;; Inspired by LNSwap, simplified & hardened
;; ------------------------------------------------------------

;; ============================
;; Errors
;; ============================
(define-constant ERR_SWAP_NOT_FOUND        (err u1000))
(define-constant ERR_TIMELOCK_NOT_REACHED  (err u1001))
(define-constant ERR_INVALID_CALLER        (err u1002))
(define-constant ERR_ZERO_AMOUNT           (err u1003))
(define-constant ERR_HASH_ALREADY_EXISTS   (err u1004))
(define-constant ERR_AMOUNT_MISMATCH       (err u1005))

;; ============================
;; Swap storage
;; ============================
(define-map swaps
  { hash: (buff 32) }
  {
    amount: uint,
    timelock: uint,
    initiator: principal,
    claimer: principal
  }
)

;; ============================================================
;; lock-stx
;; Locks STX into the contract under a hashlock + timelock
;; ============================================================
(define-public (lock-stx
    (hash (buff 32))
    (amount uint)
    (timelock uint)
    (claimer principal)
  )
  (begin
    ;; basic validation
    (asserts! (> amount u0) ERR_ZERO_AMOUNT)
    (asserts!
      (is-eq (map-get? swaps { hash: hash }) none)
      ERR_HASH_ALREADY_EXISTS
    )

    ;; move STX into contract
    (try! (stx-transfer? amount tx-sender current-contract))

    ;; store swap
    (map-set swaps
      { hash: hash }
      {
        amount: amount,
        timelock: timelock,
        initiator: tx-sender,
        claimer: claimer
      }
    )

    (print { event: "lock", hash: hash })
    (ok true)
  )
)

;; ============================================================
;; claim-stx
;; Claims locked STX by revealing the preimage
;; ============================================================
(define-public (claim-stx
    (preimage (buff 32))
    (amount uint)
  )
  (let (
        (hash (sha256 preimage))
        (swap (unwrap! (map-get? swaps { hash: hash }) ERR_SWAP_NOT_FOUND))
      )
    (asserts!
      (is-eq tx-sender (get claimer swap))
      ERR_INVALID_CALLER
    )

    (asserts!
      (is-eq amount (get amount swap))
      ERR_AMOUNT_MISMATCH
    )

    ;; remove swap first (re-entrancy safety)
    (map-delete swaps { hash: hash })

    ;; payout
    (try! (as-contract
      (stx-transfer? amount current-contract tx-sender)
    ))

    (print { event: "claim", hash: hash })
    (ok true)
  )
)

;; ============================================================
;; refund-stx
;; Refunds STX to initiator after timelock expiry
;; ============================================================
(define-public (refund-stx (hash (buff 32)))
  (let (
        (swap (unwrap! (map-get? swaps { hash: hash }) ERR_SWAP_NOT_FOUND))
        (amount (get amount swap))
      )
    (asserts!
      (> burn-block-height (get timelock swap))
      ERR_TIMELOCK_NOT_REACHED
    )

    (asserts!
      (is-eq tx-sender (get initiator swap))
      ERR_INVALID_CALLER
    )

    ;; remove swap
    (map-delete swaps { hash: hash })

    ;; refund
    (try! (as-contract
      (stx-transfer? amount current-contract tx-sender)
    ))

    (print { event: "refund", hash: hash })
    (ok true)
  )
)

;; ============================================================
;; read-only helpers
;; ============================================================
(define-read-only (get-swap (hash (buff 32)))
  (map-get? swaps { hash: hash })
)
