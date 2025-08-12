;; Academic Achievement Blockchain Contract
;; Records standardized test scores, grades, and educational milestones

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-ALREADY-EXISTS (err u501))
(define-constant ERR-NOT-FOUND (err u502))
(define-constant ERR-INVALID-INPUT (err u503))
(define-constant ERR-INVALID-SCORE (err u504))
(define-constant ERR-DUPLICATE-ACHIEVEMENT (err u505))

;; Data Variables
(define-data-var next-achievement-id uint u1)

;; Data Maps
(define-map achievements
  uint
  {
    student: principal,
    achievement-type: (string-ascii 50),
    title: (string-ascii 200),
    description: (string-ascii 500),
    score: (optional uint),
    max-score: (optional uint),
    percentile: (optional uint),
    date-achieved: uint,
    issuing-authority: principal,
    verification-code: (string-ascii 100),
    verified: bool,
    public: bool
  }
)

(define-map student-achievements
  principal
  {
    total-achievements: uint,
    achievement-ids: (list 500 uint),
    last-updated: uint
  }
)

(define-map achievement-types
  (string-ascii 50)
  {
    name: (string-ascii 200),
    category: (string-ascii 100),
    scoring-system: (string-ascii 50),
    max-possible-score: uint,
    active: bool
  }
)

(define-map authorized-authorities
  principal
  {
    name: (string-ascii 200),
    authority-type: (string-ascii 100),
    authorized-types: (list 20 (string-ascii 50)),
    verified-at: uint,
    active: bool
  }
)

(define-map student-portfolios
  principal
  {
    gpa: uint,
    class-rank: (optional uint),
    total-students: (optional uint),
    honors: (list 20 (string-ascii 100)),
    awards: (list 50 uint),
    test-scores: (list 100 uint),
    last-calculated: uint
  }
)

(define-map milestone-tracking
  { student: principal, milestone-type: (string-ascii 50) }
  {
    achieved: bool,
    achievement-date: uint,
    achievement-id: uint
  }
)

;; Private Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-authorized-authority (authority principal))
  (match (map-get? authorized-authorities authority)
    auth-data (get active auth-data)
    false
  )
)

(define-private (can-issue-achievement-type (authority principal) (achievement-type (string-ascii 50)))
  (match (map-get? authorized-authorities authority)
    auth-data
    (and (get active auth-data)
         (is-some (index-of (get authorized-types auth-data) achievement-type)))
    false
  )
)

(define-private (validate-score (score uint) (max-score uint))
  (<= score max-score)
)

(define-private (calculate-percentile (score uint) (max-score uint))
  (if (> max-score u0)
    (/ (* score u100) max-score)
    u0
  )
)

;; Public Functions

;; Add achievement type (only contract owner)
(define-public (add-achievement-type
  (type-code (string-ascii 50))
  (name (string-ascii 200))
  (category (string-ascii 100))
  (scoring-system (string-ascii 50))
  (max-possible-score uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> (len type-code) u0) ERR-INVALID-INPUT)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len category) u0) ERR-INVALID-INPUT)
    (asserts! (> max-possible-score u0) ERR-INVALID-INPUT)
    (ok (map-set achievement-types type-code {
      name: name,
      category: category,
      scoring-system: scoring-system,
      max-possible-score: max-possible-score,
      active: true
    }))
  )
)

;; Authorize achievement authority (only contract owner)
(define-public (authorize-authority
  (authority principal)
  (name (string-ascii 200))
  (authority-type (string-ascii 100))
  (authorized-types (list 20 (string-ascii 50))))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len authority-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len authorized-types) u0) ERR-INVALID-INPUT)
    (ok (map-set authorized-authorities authority {
      name: name,
      authority-type: authority-type,
      authorized-types: authorized-types,
      verified-at: block-height,
      active: true
    }))
  )
)

;; Record achievement (only authorized authorities)
(define-public (record-achievement
  (student principal)
  (achievement-type (string-ascii 50))
  (title (string-ascii 200))
  (description (string-ascii 500))
  (score (optional uint))
  (verification-code (string-ascii 100))
  (public bool))
  (let
    (
      (achievement-id (var-get next-achievement-id))
      (type-data (unwrap! (map-get? achievement-types achievement-type) ERR-NOT-FOUND))
      (current-achievements (default-to
        { total-achievements: u0, achievement-ids: (list), last-updated: u0 }
        (map-get? student-achievements student)
      ))
      (max-score (get max-possible-score type-data))
      (calculated-percentile (match score
        s (some (calculate-percentile s max-score))
        none
      ))
    )
    (asserts! (can-issue-achievement-type tx-sender achievement-type) ERR-NOT-AUTHORIZED)
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (> (len verification-code) u0) ERR-INVALID-INPUT)

    ;; Validate score if provided
    (match score
      s (asserts! (validate-score s max-score) ERR-INVALID-SCORE)
      true
    )

    (map-set achievements achievement-id {
      student: student,
      achievement-type: achievement-type,
      title: title,
      description: description,
      score: score,
      max-score: (some max-score),
      percentile: calculated-percentile,
      date-achieved: block-height,
      issuing-authority: tx-sender,
      verification-code: verification-code,
      verified: true,
      public: public
    })

    (map-set student-achievements student {
      total-achievements: (+ (get total-achievements current-achievements) u1),
      achievement-ids: (unwrap! (as-max-len? (append (get achievement-ids current-achievements) achievement-id) u500) ERR-INVALID-INPUT),
      last-updated: block-height
    })

    (var-set next-achievement-id (+ achievement-id u1))
    (ok achievement-id)
  )
)

;; Update student portfolio
(define-public (update-portfolio
  (student principal)
  (gpa uint)
  (class-rank (optional uint))
  (total-students (optional uint))
  (honors (list 20 (string-ascii 100))))
  (let
    (
      (current-portfolio (map-get? student-portfolios student))
      (existing-awards (match current-portfolio
        portfolio (get awards portfolio)
        (list)
      ))
      (existing-test-scores (match current-portfolio
        portfolio (get test-scores portfolio)
        (list)
      ))
    )
    (asserts! (is-authorized-authority tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= gpa u400) ERR-INVALID-INPUT) ;; GPA out of 4.00 (scaled by 100)
    (ok (map-set student-portfolios student {
      gpa: gpa,
      class-rank: class-rank,
      total-students: total-students,
      honors: honors,
      awards: existing-awards,
      test-scores: existing-test-scores,
      last-calculated: block-height
    }))
  )
)

;; Mark milestone achieved
(define-public (mark-milestone (student principal) (milestone-type (string-ascii 50)) (achievement-id uint))
  (begin
    (asserts! (is-authorized-authority tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? achievements achievement-id)) ERR-NOT-FOUND)
    (ok (map-set milestone-tracking
      { student: student, milestone-type: milestone-type }
      {
        achieved: true,
        achievement-date: block-height,
        achievement-id: achievement-id
      }
    ))
  )
)

;; Verify achievement
(define-public (verify-achievement (achievement-id uint) (verification-code (string-ascii 100)))
  (match (map-get? achievements achievement-id)
    achievement-data
    (ok (and (get verified achievement-data)
             (is-eq (get verification-code achievement-data) verification-code)))
    ERR-NOT-FOUND
  )
)

;; Revoke achievement (only issuing authority)
(define-public (revoke-achievement (achievement-id uint))
  (match (map-get? achievements achievement-id)
    achievement-data
    (begin
      (asserts! (is-eq tx-sender (get issuing-authority achievement-data)) ERR-NOT-AUTHORIZED)
      (ok (map-set achievements achievement-id (merge achievement-data { verified: false })))
    )
    ERR-NOT-FOUND
  )
)

;; Read-only Functions

;; Get achievement details
(define-read-only (get-achievement (achievement-id uint))
  (match (map-get? achievements achievement-id)
    achievement-data
    (if (or (get public achievement-data)
            (is-eq tx-sender (get student achievement-data))
            (is-authorized-authority tx-sender))
      (some achievement-data)
      none
    )
    none
  )
)

;; Get student achievements
(define-read-only (get-student-achievements (student principal))
  (if (or (is-eq tx-sender student) (is-authorized-authority tx-sender))
    (map-get? student-achievements student)
    none
  )
)

;; Get student portfolio
(define-read-only (get-student-portfolio (student principal))
  (if (or (is-eq tx-sender student) (is-authorized-authority tx-sender))
    (map-get? student-portfolios student)
    none
  )
)

;; Get achievement type
(define-read-only (get-achievement-type (type-code (string-ascii 50)))
  (map-get? achievement-types type-code)
)

;; Get authorized authority
(define-read-only (get-authorized-authority (authority principal))
  (map-get? authorized-authorities authority)
)

;; Check milestone status
(define-read-only (get-milestone-status (student principal) (milestone-type (string-ascii 50)))
  (map-get? milestone-tracking { student: student, milestone-type: milestone-type })
)

;; Check if authority is authorized
(define-read-only (is-authority-authorized (authority principal))
  (is-authorized-authority authority)
)

;; Get total achievements
(define-read-only (get-total-achievements)
  (- (var-get next-achievement-id) u1)
)

;; Get public achievements for student
(define-read-only (get-public-achievements (student principal))
  (map-get? student-achievements student)
)
