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
(define-constant ERR-INVALID-RATING (err u109))
(define-constant ERR-ALREADY-RATED (err u110))
(define-constant ERR-NOT-PATIENT (err u111))
(define-constant ERR-NOT-COMPLETED (err u112))
(define-constant ERR-SUBSCRIPTION-EXISTS (err u113))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u114))
(define-constant ERR-SUBSCRIPTION-INACTIVE (err u115))
(define-constant ERR-INVALID-FREQUENCY (err u116))
(define-constant ERR-PAYMENT-NOT-DUE (err u117))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant PLATFORM-FEE-PERCENT u3)
(define-constant CONSULTATION-TIMEOUT-BLOCKS u144)
(define-constant DISPUTE-RESOLUTION-BLOCKS u1008)
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)
(define-constant RATING-SCALE u100)

;; Data Variables
(define-data-var total-consultations uint u0)
(define-data-var total-fees-collected uint u0)
(define-data-var platform-paused bool false)
(define-data-var total-subscriptions uint u0)

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

(define-map doctor-ratings principal {
    total-score: uint,
    rating-count: uint,
    average-rating: uint
})

(define-map consultation-ratings uint {
    rated: bool,
    rating: uint,
    rated-at-block: uint
})

(define-map subscriptions uint {
    patient: principal,
    doctor: principal,
    frequency-blocks: uint,
    amount-per-consultation: uint,
    prepaid-consultations: uint,
    used-consultations: uint,
    active: bool,
    created-at-block: uint,
    last-payment-block: uint,
    next-due-block: uint
})

(define-map patient-subscriptions principal (list 20 uint))
(define-map doctor-subscriptions principal (list 50 uint))

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

(define-public (submit-rating (consultation-id uint) (rating uint))
    (let (
        (consultation (unwrap! (map-get? consultations consultation-id) ERR-NOT-FOUND))
        (patient (get patient consultation))
        (doctor (get doctor consultation))
        (consultation-rating (map-get? consultation-ratings consultation-id))
        (current-doctor-rating (default-to { total-score: u0, rating-count: u0, average-rating: u0 } 
                                           (map-get? doctor-ratings doctor)))
        (new-total-score (+ (get total-score current-doctor-rating) rating))
        (new-rating-count (+ (get rating-count current-doctor-rating) u1))
        (new-average-rating (/ (* new-total-score RATING-SCALE) new-rating-count))
    )
        (asserts! (is-eq tx-sender patient) ERR-NOT-PATIENT)
        (asserts! (is-eq (get status consultation) "completed") ERR-NOT-COMPLETED)
        (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) ERR-INVALID-RATING)
        (asserts! (is-none consultation-rating) ERR-ALREADY-RATED)
        
        (map-set consultation-ratings consultation-id {
            rated: true,
            rating: rating,
            rated-at-block: stacks-block-height
        })
        
        (map-set doctor-ratings doctor {
            total-score: new-total-score,
            rating-count: new-rating-count,
            average-rating: new-average-rating
        })
        
        (ok true)
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
        platform-paused: (var-get platform-paused),
        total-subscriptions: (var-get total-subscriptions)
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

(define-read-only (get-doctor-rating (doctor principal))
    (map-get? doctor-ratings doctor)
)

(define-read-only (get-consultation-rating (consultation-id uint))
    (map-get? consultation-ratings consultation-id)
)

(define-read-only (has-consultation-been-rated (consultation-id uint))
    (let (
        (rating-data (map-get? consultation-ratings consultation-id))
    )
        (match rating-data
            some-rating (get rated some-rating)
            false
        )
    )
)

(define-read-only (get-doctor-average-rating (doctor principal))
    (let (
        (rating-data (map-get? doctor-ratings doctor))
    )
        (match rating-data
            some-rating (get average-rating some-rating)
            u0
        )
    )
)

(define-read-only (doctor-meets-min-rating (doctor principal) (min-rating uint))
    (let (
        (doctor-average (get-doctor-average-rating doctor))
        (min-rating-scaled (* min-rating RATING-SCALE))
    )
        (>= doctor-average min-rating-scaled)
    )
)

(define-public (create-subscription (doctor principal) (frequency-blocks uint) (prepaid-consultations uint))
    (let (
        (subscription-id (+ (var-get total-subscriptions) u1))
        (doctor-data (unwrap! (map-get? doctors doctor) ERR-NOT-FOUND))
        (patient-data (unwrap! (map-get? patients tx-sender) ERR-NOT-FOUND))
        (consultation-rate (get rate-per-consultation doctor-data))
        (platform-fee-per-consultation (/ (* consultation-rate PLATFORM-FEE-PERCENT) u100))
        (total-per-consultation (+ consultation-rate platform-fee-per-consultation))
        (total-amount (* total-per-consultation prepaid-consultations))
        (current-patient-subs (default-to (list) (map-get? patient-subscriptions tx-sender)))
        (current-doctor-subs (default-to (list) (map-get? doctor-subscriptions doctor)))
    )
        (asserts! (get active doctor-data) ERR-UNAUTHORIZED)
        (asserts! (get active patient-data) ERR-UNAUTHORIZED)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        (asserts! (> frequency-blocks u0) ERR-INVALID-FREQUENCY)
        (asserts! (> prepaid-consultations u0) ERR-INVALID-AMOUNT)
        (asserts! (< (len current-patient-subs) u20) ERR-SUBSCRIPTION-EXISTS)
        (asserts! (< (len current-doctor-subs) u50) ERR-SUBSCRIPTION-EXISTS)
        
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
        
        (map-set subscriptions subscription-id {
            patient: tx-sender,
            doctor: doctor,
            frequency-blocks: frequency-blocks,
            amount-per-consultation: total-per-consultation,
            prepaid-consultations: prepaid-consultations,
            used-consultations: u0,
            active: true,
            created-at-block: stacks-block-height,
            last-payment-block: stacks-block-height,
            next-due-block: (+ stacks-block-height frequency-blocks)
        })
        
        (map-set patient-subscriptions tx-sender (unwrap! (as-max-len? (append current-patient-subs subscription-id) u20) ERR-SUBSCRIPTION-EXISTS))
        (map-set doctor-subscriptions doctor (unwrap! (as-max-len? (append current-doctor-subs subscription-id) u50) ERR-SUBSCRIPTION-EXISTS))
        
        (var-set total-subscriptions subscription-id)
        (ok subscription-id)
    )
)

(define-public (use-subscription-consultation (subscription-id uint))
    (let (
        (subscription (unwrap! (map-get? subscriptions subscription-id) ERR-SUBSCRIPTION-NOT-FOUND))
        (consultation-id (+ (var-get total-consultations) u1))
        (patient (get patient subscription))
        (doctor (get doctor subscription))
        (doctor-data (unwrap! (map-get? doctors doctor) ERR-NOT-FOUND))
        (patient-data (unwrap! (map-get? patients patient) ERR-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender patient) ERR-UNAUTHORIZED)
        (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (< (get used-consultations subscription) (get prepaid-consultations subscription)) ERR-INSUFFICIENT-BALANCE)
        (asserts! (get active doctor-data) ERR-UNAUTHORIZED)
        (asserts! (get active patient-data) ERR-UNAUTHORIZED)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (map-set consultations consultation-id {
            patient: patient,
            doctor: doctor,
            amount: (- (get amount-per-consultation subscription) (/ (* (get amount-per-consultation subscription) PLATFORM-FEE-PERCENT) (+ u100 PLATFORM-FEE-PERCENT))),
            platform-fee: (/ (* (get amount-per-consultation subscription) PLATFORM-FEE-PERCENT) (+ u100 PLATFORM-FEE-PERCENT)),
            status: "booked",
            created-at-block: stacks-block-height,
            completed-at-block: none,
            notes: none
        })
        
        (map-set subscriptions subscription-id (merge subscription {
            used-consultations: (+ (get used-consultations subscription) u1)
        }))
        
        (var-set total-consultations consultation-id)
        (ok consultation-id)
    )
)

(define-public (renew-subscription (subscription-id uint) (additional-consultations uint))
    (let (
        (subscription (unwrap! (map-get? subscriptions subscription-id) ERR-SUBSCRIPTION-NOT-FOUND))
        (patient (get patient subscription))
        (doctor (get doctor subscription))
        (doctor-data (unwrap! (map-get? doctors doctor) ERR-NOT-FOUND))
        (total-amount (* (get amount-per-consultation subscription) additional-consultations))
    )
        (asserts! (is-eq tx-sender patient) ERR-UNAUTHORIZED)
        (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (get active doctor-data) ERR-UNAUTHORIZED)
        (asserts! (> additional-consultations u0) ERR-INVALID-AMOUNT)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
        
        (map-set subscriptions subscription-id (merge subscription {
            prepaid-consultations: (+ (get prepaid-consultations subscription) additional-consultations),
            last-payment-block: stacks-block-height,
            next-due-block: (+ stacks-block-height (get frequency-blocks subscription))
        }))
        
        (ok true)
    )
)

(define-public (cancel-subscription (subscription-id uint))
    (let (
        (subscription (unwrap! (map-get? subscriptions subscription-id) ERR-SUBSCRIPTION-NOT-FOUND))
        (patient (get patient subscription))
        (doctor (get doctor subscription))
        (remaining-consultations (- (get prepaid-consultations subscription) (get used-consultations subscription)))
        (refund-amount (* (get amount-per-consultation subscription) remaining-consultations))
    )
        (asserts! (or (is-eq tx-sender patient) (is-eq tx-sender doctor)) ERR-UNAUTHORIZED)
        (asserts! (get active subscription) ERR-SUBSCRIPTION-INACTIVE)
        (asserts! (not (var-get platform-paused)) ERR-UNAUTHORIZED)
        
        (map-set subscriptions subscription-id (merge subscription { active: false }))
        
        (if (> refund-amount u0)
            (try! (as-contract (stx-transfer? refund-amount tx-sender patient)))
            true
        )
        
        (ok true)
    )
)

(define-read-only (get-subscription (subscription-id uint))
    (map-get? subscriptions subscription-id)
)

(define-read-only (get-patient-subscriptions (patient principal))
    (map-get? patient-subscriptions patient)
)

(define-read-only (get-doctor-subscriptions (doctor principal))
    (map-get? doctor-subscriptions doctor)
)

(define-read-only (get-subscription-balance (subscription-id uint))
    (let (
        (subscription (map-get? subscriptions subscription-id))
    )
        (match subscription
            some-subscription
                (some (- (get prepaid-consultations some-subscription) (get used-consultations some-subscription)))
            none
        )
    )
)

(define-read-only (is-subscription-renewable (subscription-id uint))
    (let (
        (subscription (map-get? subscriptions subscription-id))
    )
        (match subscription
            some-subscription
                (and 
                    (get active some-subscription)
                    (<= (get next-due-block some-subscription) stacks-block-height)
                )
            false
        )
    )
)

(define-read-only (calculate-subscription-cost (doctor principal) (consultation-count uint))
    (let (
        (doctor-data (map-get? doctors doctor))
    )
        (match doctor-data
            some-doctor
                (let (
                    (consultation-rate (get rate-per-consultation some-doctor))
                    (platform-fee-per-consultation (/ (* consultation-rate PLATFORM-FEE-PERCENT) u100))
                    (total-per-consultation (+ consultation-rate platform-fee-per-consultation))
                )
                    (some (* total-per-consultation consultation-count))
                )
            none
        )
    )
)
