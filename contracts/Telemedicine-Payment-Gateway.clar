;; title: Telemedicine-Payment-Gateway
;; version: 1.0.0
;; summary: Secure payment gateway for virtual medical consultations with escrow functionality
;; description: Enables secure, instant payments for telemedicine consultations with dispute resolution

;; Error codes
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INSUFFICIENT-BALANCE (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-UNAUTHORIZED (err u105))
(define-constant ERR-INVALID-STATUS (err u106))
(define-constant ERR-CONSULTATION-EXPIRED (err u107))
(define-constant ERR-DISPUTE-EXISTS (err u108))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-PERCENT u3)
(define-constant CONSULTATION-TIMEOUT-BLOCKS u144)
(define-constant DISPUTE-RESOLUTION-BLOCKS u1008)

;; Data Variables
(define-data-var total-consultations uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var platform-paused bool false)

;; Data Maps
(define-map doctors principal {
    name: (string-utf8 100),
    specialty: (string-utf8 50),
    rate-per-consultation: uint,
    total-consultations: uint,
    rating: uint,
    active: bool,
    registration-block: uint
})

(define-map patients principal {
    name: (string-utf8 100),
    total-consultations: uint,
    active: bool,
    registration-block: uint
})

(define-map consultations uint {
    patient: principal,
    doctor: principal,
    amount: uint,
    platform-fee: uint,
    status: (string-ascii 20),
    created-at-block: uint,
    completed-at-block: (optional uint),
    notes: (optional (string-utf8 500))
})

(define-map escrow uint {
    amount: uint,
    released: bool,
    dispute-raised: bool,
    dispute-resolved: bool
})

(define-map disputes uint {
    raised-by: principal,
    reason: (string-utf8 200),
    created-at-block: uint,
    resolved: bool,
    resolution: (optional (string-utf8 200)),
    winner: (optional principal)
})

(define-map doctor-availability principal {
    available: bool,
    next-available-block: uint,
    consultation-duration-blocks: uint
})

;; Public Functions

(define-public (register-doctor (name (string-utf8 100)) (specialty (string-utf8 50)) (rate uint))
    (let ((doctor-exists (is-some (map-get? doctors tx-sender))))
        (asserts! (not doctor-exists) ERR-ALREADY-EXISTS)
        (asserts! (> rate u0) ERR-INVALID-AMOUNT)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        (ok (map-set doctors tx-sender {
            name: name,
            specialty: specialty,
            rate-per-consultation: rate,
            total-consultations: u0,
            rating: u5,
            active: true,
            registration-block: stacks-block-height
        }))
    )
)

(define-public (register-patient (name (string-utf8 100)))
    (let ((patient-exists (is-some (map-get? patients tx-sender))))
        (asserts! (not patient-exists) ERR-ALREADY-EXISTS)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        (ok (map-set patients tx-sender {
            name: name,
            total-consultations: u0,
            active: true,
            registration-block: stacks-block-height
        }))
    )
)

(define-public (book-consultation (doctor principal))
    (let (
        (consultation-id (+ (var-get total-consultations) u1))
        (doctor-data (unwrap! (map-get? doctors doctor) ERR-NOT-FOUND))
        (patient-data (unwrap! (map-get? patients tx-sender) ERR-NOT-FOUND))
        (consultation-fee (get rate-per-consultation doctor-data))
        (platform-fee (/ (* consultation-fee PLATFORM-FEE-PERCENT) u100))
        (total-amount (+ consultation-fee platform-fee))
    )
        (asserts! (get active doctor-data) ERR-UNAUTHORIZED)
        (asserts! (get active patient-data) ERR-UNAUTHORIZED)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
        
        (map-set consultations consultation-id {
            patient: tx-sender,
            doctor: doctor,
            amount: consultation-fee,
            platform-fee: platform-fee,
            status: "booked",
            created-at-block: stacks-block-height,
            completed-at-block: none,
            notes: none
        })
        
        (map-set escrow consultation-id {
            amount: total-amount,
            released: false,
            dispute-raised: false,
            dispute-resolved: false
        })
        
        (var-set total-consultations consultation-id)
        (ok consultation-id)
    )
)

(define-public (start-consultation (consultation-id uint))
    (let (
        (consultation (unwrap! (map-get? consultations consultation-id) ERR-NOT-FOUND))
        (doctor (get doctor consultation))
    )
        (asserts! (is-eq tx-sender doctor) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status consultation) "booked") ERR-INVALID-STATUS)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (ok (map-set consultations consultation-id 
            (merge consultation { status: "in-progress" })
        ))
    )
)

(define-public (complete-consultation (consultation-id uint) (notes (optional (string-utf8 500))))
    (let (
        (consultation (unwrap! (map-get? consultations consultation-id) ERR-NOT-FOUND))
        (doctor (get doctor consultation))
        (patient (get patient consultation))
        (escrow-data (unwrap! (map-get? escrow consultation-id) ERR-NOT-FOUND))
        (doctor-data (unwrap! (map-get? doctors doctor) ERR-NOT-FOUND))
        (patient-data (unwrap! (map-get? patients patient) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender doctor) ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status consultation) "in-progress") ERR-INVALID-STATUS)
        (asserts! (not (get released escrow-data)) ERR-INVALID-STATUS)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (try! (as-contract (stx-transfer? (get amount consultation) tx-sender doctor)))
        (try! (as-contract (stx-transfer? (get platform-fee consultation) tx-sender CONTRACT-OWNER)))
        
        (map-set consultations consultation-id (merge consultation {
            status: "completed",
            completed-at-block: (some stacks-block-height),
            notes: notes
        }))
        
        (map-set escrow consultation-id (merge escrow-data { released: true }))
        
        (map-set doctors doctor (merge doctor-data {
            total-consultations: (+ (get total-consultations doctor-data) u1)
        }))
        
        (map-set patients patient (merge patient-data {
            total-consultations: (+ (get total-consultations patient-data) u1)
        }))
        
        (var-set total-fees-collected (+ (var-get total-fees-collected) (get platform-fee consultation)))
        (ok true)
    )
)

(define-public (raise-dispute (consultation-id uint) (reason (string-utf8 200)))
    (let (
        (consultation (unwrap! (map-get? consultations consultation-id) ERR-NOT-FOUND))
        (escrow-data (unwrap! (map-get? escrow consultation-id) ERR-NOT-FOUND))
        (patient (get patient consultation))
        (doctor (get doctor consultation))
    )
        (asserts! (or (is-eq tx-sender patient) (is-eq tx-sender doctor)) ERR-UNAUTHORIZED)
        (asserts! (not (get dispute-raised escrow-data)) ERR-DISPUTE-EXISTS)
        (asserts! (not (get released escrow-data)) ERR-INVALID-STATUS)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (map-set disputes consultation-id {
            raised-by: tx-sender,
            reason: reason,
            created-at-block: stacks-block-height,
            resolved: false,
            resolution: none,
            winner: none
        })
        
        (map-set escrow consultation-id (merge escrow-data { dispute-raised: true }))
        (map-set consultations consultation-id (merge consultation { status: "disputed" }))
        
        (ok true)
    )
)

(define-public (resolve-dispute (consultation-id uint) (winner principal) (resolution (string-utf8 200)))
    (let (
        (consultation (unwrap! (map-get? consultations consultation-id) ERR-NOT-FOUND))
        (escrow-data (unwrap! (map-get? escrow consultation-id) ERR-NOT-FOUND))
        (dispute-data (unwrap! (map-get? disputes consultation-id) ERR-NOT-FOUND))
        (patient (get patient consultation))
        (doctor (get doctor consultation))
        (total-amount (get amount escrow-data))
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (asserts! (get dispute-raised escrow-data) ERR-NOT-FOUND)
        (asserts! (not (get resolved dispute-data)) ERR-INVALID-STATUS)
        (asserts! (or (is-eq winner patient) (is-eq winner doctor)) ERR-UNAUTHORIZED)
        
        (try! (as-contract (stx-transfer? total-amount tx-sender winner)))
        
        (map-set disputes consultation-id (merge dispute-data {
            resolved: true,
            resolution: (some resolution),
            winner: (some winner)
        }))
        
        (map-set escrow consultation-id (merge escrow-data {
            released: true,
            dispute-resolved: true
        }))
        
        (map-set consultations consultation-id (merge consultation { status: "resolved" }))
        
        (ok true)
    )
)

(define-public (set-doctor-availability (available bool) (next-available-block uint) (duration-blocks uint))
    (let ((doctor-exists (is-some (map-get? doctors tx-sender))))
        (asserts! doctor-exists ERR-NOT-FOUND)
        (ok (map-set doctor-availability tx-sender {
            available: available,
            next-available-block: next-available-block,
            consultation-duration-blocks: duration-blocks
        }))
    )
)

(define-public (update-doctor-rate (new-rate uint))
    (let (
        (doctor-data (unwrap! (map-get? doctors tx-sender) ERR-NOT-FOUND))
    )
        (asserts! (> new-rate u0) ERR-INVALID-AMOUNT)
        (ok (map-set doctors tx-sender (merge doctor-data {
            rate-per-consultation: new-rate
        })))
    )
)

(define-public (toggle-platform-pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        (ok (var-set platform-paused (not (var-get platform-paused))))
    )
)

;; Read-only functions

(define-read-only (get-doctor (doctor principal))
    (map-get? doctors doctor)
)

(define-read-only (get-patient (patient principal))
    (map-get? patients patient)
)

(define-read-only (get-consultation (consultation-id uint))
    (map-get? consultations consultation-id)
)

(define-read-only (get-escrow-status (consultation-id uint))
    (map-get? escrow consultation-id)
)

(define-read-only (get-dispute (consultation-id uint))
    (map-get? disputes consultation-id)
)

(define-read-only (get-doctor-availability (doctor principal))
    (map-get? doctor-availability doctor)
)

(define-read-only (get-platform-stats)
    {
        total-consultations: (var-get total-consultations),
        total-fees-collected: (var-get total-fees-collected),
        platform-paused: (var-get platform-paused)
    }
)

(define-read-only (is-consultation-expired (consultation-id uint))
    (let (
        (consultation (map-get? consultations consultation-id))
    )
        (match consultation
            some-consultation 
                (let ((created-block (get created-at-block some-consultation)))
                    (> (- stacks-block-height created-block) CONSULTATION-TIMEOUT-BLOCKS)
                )
            false
        )
    )
)

(define-read-only (calculate-consultation-fee (doctor principal))
    (let (
        (doctor-data (map-get? doctors doctor))
    )
        (match doctor-data
            some-doctor
                (let (
                    (base-fee (get rate-per-consultation some-doctor))
                    (platform-fee (/ (* base-fee PLATFORM-FEE-PERCENT) u100))
                )
                    (some (+ base-fee platform-fee))
                )
            none
        )
    )
)
