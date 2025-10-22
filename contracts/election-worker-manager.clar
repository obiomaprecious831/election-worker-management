;; Election Worker Manager Smart Contract
;; Manages poll worker recruitment, training, and assignment coordination

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-not-trained (err u105))
(define-constant err-already-assigned (err u106))
(define-constant err-location-full (err u107))
(define-constant err-invalid-input (err u108))

;; Worker status constants
(define-constant status-available u1)
(define-constant status-assigned u2)
(define-constant status-unavailable u3)
(define-constant status-checked-in u4)

;; Data Variables
(define-data-var next-worker-id uint u1)
(define-data-var next-location-id uint u1)
(define-data-var next-assignment-id uint u1)

;; Data Maps

;; Worker information
(define-map workers
  principal
  {
    worker-id: uint,
    name: (string-ascii 100),
    email: (string-ascii 100),
    phone: (string-ascii 20),
    status: uint,
    is-trained: bool,
    training-date: uint,
    experience-level: uint,
    total-assignments: uint,
    registered-at: uint
  }
)

;; Polling location information
(define-map polling-locations
  uint
  {
    location-name: (string-ascii 200),
    address: (string-ascii 300),
    required-workers: uint,
    current-workers: uint,
    is-active: bool,
    election-date: uint,
    created-by: principal,
    created-at: uint
  }
)

;; Worker assignments to polling locations
(define-map assignments
  uint
  {
    worker: principal,
    location-id: uint,
    election-date: uint,
    assigned-at: uint,
    assigned-by: principal,
    is-checked-in: bool,
    check-in-time: uint,
    role: (string-ascii 50)
  }
)

;; Track worker assignments by worker address
(define-map worker-assignments
  { worker: principal, election-date: uint }
  uint ;; assignment-id
)

;; Track location assignments count
(define-map location-assignment-count
  { location-id: uint, election-date: uint }
  uint
)

;; Administrator permissions
(define-map administrators principal bool)

;; Initialize contract owner as administrator
(map-set administrators contract-owner true)

;; Private Functions

(define-private (is-administrator (user principal))
  (default-to false (map-get? administrators user))
)

(define-private (get-next-worker-id)
  (let ((current-id (var-get next-worker-id)))
    (var-set next-worker-id (+ current-id u1))
    current-id
  )
)

(define-private (get-next-location-id)
  (let ((current-id (var-get next-location-id)))
    (var-set next-location-id (+ current-id u1))
    current-id
  )
)

(define-private (get-next-assignment-id)
  (let ((current-id (var-get next-assignment-id)))
    (var-set next-assignment-id (+ current-id u1))
    current-id
  )
)

;; Public Functions

;; Administrative Functions

(define-public (add-administrator (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set administrators new-admin true))
  )
)

(define-public (remove-administrator (admin principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (is-eq admin contract-owner)) err-unauthorized)
    (ok (map-delete administrators admin))
  )
)

;; Worker Management Functions

(define-public (register-worker (worker-address principal) (name (string-ascii 100)) (email (string-ascii 100)) (phone (string-ascii 20)))
  (let
    (
      (worker-id (get-next-worker-id))
    )
    (asserts! (is-none (map-get? workers worker-address)) err-already-exists)
    (asserts! (> (len name) u0) err-invalid-input)
    (asserts! (> (len email) u0) err-invalid-input)
    (ok (map-set workers worker-address {
      worker-id: worker-id,
      name: name,
      email: email,
      phone: phone,
      status: status-available,
      is-trained: false,
      training-date: u0,
      experience-level: u0,
      total-assignments: u0,
      registered-at: block-height
    }))
  )
)

(define-public (complete-training (worker-address principal))
  (let
    (
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
    )
    (asserts! (or (is-administrator tx-sender) (is-eq tx-sender worker-address)) err-unauthorized)
    (ok (map-set workers worker-address
      (merge worker-data {
        is-trained: true,
        training-date: block-height
      })
    ))
  )
)

(define-public (update-worker-status (worker-address principal) (new-status uint))
  (let
    (
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
    )
    (asserts! (or (is-administrator tx-sender) (is-eq tx-sender worker-address)) err-unauthorized)
    (asserts! (or (is-eq new-status status-available) 
                  (is-eq new-status status-unavailable)) err-invalid-status)
    (ok (map-set workers worker-address
      (merge worker-data { status: new-status })
    ))
  )
)

(define-public (update-worker-info (worker-address principal) (email (string-ascii 100)) (phone (string-ascii 20)))
  (let
    (
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
    )
    (asserts! (is-eq tx-sender worker-address) err-unauthorized)
    (ok (map-set workers worker-address
      (merge worker-data {
        email: email,
        phone: phone
      })
    ))
  )
)

;; Polling Location Management Functions

(define-public (register-polling-location (location-name (string-ascii 200)) (address (string-ascii 300)) (required-workers uint) (election-date uint))
  (let
    (
      (location-id (get-next-location-id))
    )
    (asserts! (is-administrator tx-sender) err-unauthorized)
    (asserts! (> (len location-name) u0) err-invalid-input)
    (asserts! (> required-workers u0) err-invalid-input)
    (ok (map-set polling-locations location-id {
      location-name: location-name,
      address: address,
      required-workers: required-workers,
      current-workers: u0,
      is-active: true,
      election-date: election-date,
      created-by: tx-sender,
      created-at: block-height
    }))
  )
)

(define-public (update-location-capacity (location-id uint) (required-workers uint))
  (let
    (
      (location-data (unwrap! (map-get? polling-locations location-id) err-not-found))
    )
    (asserts! (is-administrator tx-sender) err-unauthorized)
    (asserts! (> required-workers u0) err-invalid-input)
    (ok (map-set polling-locations location-id
      (merge location-data { required-workers: required-workers })
    ))
  )
)

(define-public (toggle-location-status (location-id uint))
  (let
    (
      (location-data (unwrap! (map-get? polling-locations location-id) err-not-found))
    )
    (asserts! (is-administrator tx-sender) err-unauthorized)
    (ok (map-set polling-locations location-id
      (merge location-data { is-active: (not (get is-active location-data)) })
    ))
  )
)

;; Assignment Functions

(define-public (assign-worker (worker-address principal) (location-id uint) (election-date uint) (role (string-ascii 50)))
  (let
    (
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
      (location-data (unwrap! (map-get? polling-locations location-id) err-not-found))
      (assignment-id (get-next-assignment-id))
      (current-count (default-to u0 (map-get? location-assignment-count { location-id: location-id, election-date: election-date })))
    )
    (asserts! (is-administrator tx-sender) err-unauthorized)
    (asserts! (get is-trained worker-data) err-not-trained)
    (asserts! (is-eq (get status worker-data) status-available) err-invalid-status)
    (asserts! (get is-active location-data) err-invalid-status)
    (asserts! (is-none (map-get? worker-assignments { worker: worker-address, election-date: election-date })) err-already-assigned)
    (asserts! (< current-count (get required-workers location-data)) err-location-full)
    
    ;; Create assignment
    (map-set assignments assignment-id {
      worker: worker-address,
      location-id: location-id,
      election-date: election-date,
      assigned-at: block-height,
      assigned-by: tx-sender,
      is-checked-in: false,
      check-in-time: u0,
      role: role
    })
    
    ;; Update worker assignment tracking
    (map-set worker-assignments { worker: worker-address, election-date: election-date } assignment-id)
    
    ;; Update location assignment count
    (map-set location-assignment-count { location-id: location-id, election-date: election-date } (+ current-count u1))
    
    ;; Update worker status and assignment count
    (map-set workers worker-address
      (merge worker-data {
        status: status-assigned,
        total-assignments: (+ (get total-assignments worker-data) u1)
      })
    )
    
    (ok assignment-id)
  )
)

(define-public (unassign-worker (worker-address principal) (election-date uint))
  (let
    (
      (assignment-id (unwrap! (map-get? worker-assignments { worker: worker-address, election-date: election-date }) err-not-found))
      (assignment-data (unwrap! (map-get? assignments assignment-id) err-not-found))
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
      (location-id (get location-id assignment-data))
      (current-count (default-to u0 (map-get? location-assignment-count { location-id: location-id, election-date: election-date })))
    )
    (asserts! (is-administrator tx-sender) err-unauthorized)
    (asserts! (not (get is-checked-in assignment-data)) err-invalid-status)
    
    ;; Delete assignment
    (map-delete assignments assignment-id)
    (map-delete worker-assignments { worker: worker-address, election-date: election-date })
    
    ;; Update location assignment count
    (if (> current-count u0)
      (map-set location-assignment-count { location-id: location-id, election-date: election-date } (- current-count u1))
      true
    )
    
    ;; Update worker status
    (map-set workers worker-address
      (merge worker-data { status: status-available })
    )
    
    (ok true)
  )
)

(define-public (check-in-worker (worker-address principal) (election-date uint))
  (let
    (
      (assignment-id (unwrap! (map-get? worker-assignments { worker: worker-address, election-date: election-date }) err-not-found))
      (assignment-data (unwrap! (map-get? assignments assignment-id) err-not-found))
      (worker-data (unwrap! (map-get? workers worker-address) err-not-found))
    )
    (asserts! (or (is-administrator tx-sender) (is-eq tx-sender worker-address)) err-unauthorized)
    (asserts! (not (get is-checked-in assignment-data)) err-invalid-status)
    
    ;; Update assignment check-in status
    (map-set assignments assignment-id
      (merge assignment-data {
        is-checked-in: true,
        check-in-time: block-height
      })
    )
    
    ;; Update worker status
    (map-set workers worker-address
      (merge worker-data { status: status-checked-in })
    )
    
    (ok true)
  )
)

;; Read-only Functions

(define-read-only (get-worker-info (worker-address principal))
  (ok (map-get? workers worker-address))
)

(define-read-only (get-location-info (location-id uint))
  (ok (map-get? polling-locations location-id))
)

(define-read-only (get-assignment-info (assignment-id uint))
  (ok (map-get? assignments assignment-id))
)

(define-read-only (get-worker-assignment (worker-address principal) (election-date uint))
  (ok (map-get? worker-assignments { worker: worker-address, election-date: election-date }))
)

(define-read-only (get-location-worker-count (location-id uint) (election-date uint))
  (ok (map-get? location-assignment-count { location-id: location-id, election-date: election-date }))
)

(define-read-only (is-admin (user principal))
  (ok (is-administrator user))
)

(define-read-only (get-contract-owner)
  (ok contract-owner)
)


;; title: election-worker-manager
;; version:
;; summary:
;; description:

;; traits
;;

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

