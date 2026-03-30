;;; nvvo.el --- VVO public transport interface -*- lexical-binding: t; -*-
;;; Author: Mahmoud Adam <nagy@khwaternagy.com>
;;; Commentary:
;; Query Dresden/VVO public transport stops and departure monitors.

;;; Code:

(require 'url)
(require 'json)

(defvar nvvo-base-url "https://webapi.vvo-online.de"
  "Base URL for the VVO WebAPI.")

(defun nvvo--parse-point (point-string)
  "Parse a pipe-delimited POINT-STRING into an alist.
Returns nil if the point is not a stop (non-numeric ID)."
  (let ((fields (split-string point-string "|")))
    (when (and (>= (length fields) 4)
               (string-match-p "\\`[0-9]+\\'" (nth 0 fields)))
      `((id   . ,(nth 0 fields))
        (city . ,(nth 2 fields))
        (name . ,(nth 3 fields))))))

(defun nvvo--ms-date-to-time (ms-date-string)
  "Convert Microsoft JSON date MS-DATE-STRING like /Date(1234+0100)/ to readable time."
  (when (and ms-date-string
             (string-match "/Date(\\([0-9]+\\)[+-]" ms-date-string))
    (format-time-string "%H:%M" (seconds-to-time
                                  (/ (string-to-number (match-string 1 ms-date-string)) 1000)))))

(defun nvvo-point-finder (query)
  "Search for stops matching QUERY and return parsed results."
  (let* ((url (format "%s/tr/pointfinder?query=%s&stopsOnly=true&format=json"
                       nvvo-base-url (url-hexify-string query)))
         (buf (url-retrieve-synchronously url t)))
    (unwind-protect
        (with-current-buffer buf
          (set-buffer-multibyte t)
          (goto-char url-http-end-of-headers)
          (decode-coding-region (point) (point-max) 'utf-8)
          (let* ((json-object-type 'alist)
                 (resp (json-read))
                 (points (alist-get 'Points resp)))
            (delq nil (mapcar #'nvvo--parse-point (append points nil)))))
      (kill-buffer buf))))

;;;###autoload
(defun nvvo-search-stop (query)
  "Interactively search for a stop by QUERY string."
  (interactive "sSearch stop: ")
  (let ((stops (nvvo-point-finder query)))
    (if (null stops)
        (message "No stops found for '%s'" query)
      (let* ((candidates (mapcar (lambda (s)
                                   (cons (format "%s — %s (ID: %s)"
                                                 (alist-get 'name s)
                                                 (alist-get 'city s)
                                                 (alist-get 'id s))
                                         (alist-get 'id s)))
                                 stops))
             (choice (completing-read "Select stop: " candidates nil t))
             (stop-id (cdr (assoc choice candidates))))
        (when stop-id
          (nvvo-departure-monitor stop-id))))))

(defun nvvo--fetch-departures (stop-id &optional limit walk-minutes)
  "Fetch departures for STOP-ID, returning the parsed JSON response.
LIMIT defaults to 10.  WALK-MINUTES offsets the query time."
  (let* ((url-request-method "POST")
         (url-request-extra-headers '(("Content-Type" . "application/json; charset=utf-8")))
         (time-offset (if (and walk-minutes (> walk-minutes 0))
                          (format-time-string "%Y-%m-%dT%H:%M:%SZ"
                                              (time-add nil (* walk-minutes 60))
                                              t)
                        nil))
         (payload `((stopid . ,stop-id)
		    (limit  . ,(or limit 20))
                    (mot    . ["Tram" "CityBus" "IntercityBus" "SuburbanRailway"
                               "Train" "Cableway" "Ferry" "HailedSharedTaxi"])
                    (format . "json")))
         (_ (when time-offset
              (setq payload (append payload `((time . ,time-offset))))))
         (url-request-data (encode-coding-string (json-encode payload) 'utf-8))
         (buf (url-retrieve-synchronously (concat nvvo-base-url "/dm") t)))
    (unwind-protect
        (with-current-buffer buf
          (set-buffer-multibyte t)
          (goto-char url-http-end-of-headers)
          (decode-coding-region (point) (point-max) 'utf-8)
          (let ((json-object-type 'alist))
            (json-read)))
      (kill-buffer buf))))

;;;###autoload
(defvar-local nvvo--buffer-stop-id nil
  "Stop ID associated with the current departures buffer.")

(defvar nvvo-departure-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "g" #'nvvo-departure-refresh)
    map))

(define-derived-mode nvvo-departure-mode special-mode "VVO-Departures"
  "Mode for VVO departure monitor buffers.")

(defun nvvo-departure-refresh ()
  "Refresh the current departures buffer."
  (interactive)
  (when nvvo--buffer-stop-id
    (nvvo-departure-monitor nvvo--buffer-stop-id)))

(defun nvvo-departure-monitor (stop-id)
  "Display upcoming departures for STOP-ID in a buffer."
  (interactive "sStop ID: ")
  (let* ((resp (nvvo--fetch-departures stop-id))
         (name (alist-get 'Name resp))
         (place (alist-get 'Place resp))
         (deps (alist-get 'Departures resp))
         (buf (get-buffer-create "*VVO Departures*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Departures: %s, %s (ID: %s)  [%s]\n"
                       (or name "?") (or place "?") stop-id
                       (format-time-string "%H:%M:%S")))
        (insert "Press 'g' to refresh\n")
        (insert (make-string 60 ?─) "\n")
        (insert (format "%-6s %-20s %-10s %s\n" "Line" "Direction" "Time" "Delay"))
        (insert (make-string 60 ?─) "\n")
        (if (null deps)
            (insert "No departures found.\n")
          (seq-doseq (dep (append deps nil))
            (let* ((line      (alist-get 'LineName dep))
                   (direction (alist-get 'Direction dep))
                   (sched     (nvvo--ms-date-to-time (alist-get 'ScheduledTime dep)))
                   (real      (nvvo--ms-date-to-time (alist-get 'RealTime dep)))
                   (delay     (if (and sched real (not (string= sched real)))
                                  (format "→ %s" real)
                                "")))
              (insert (format "%-6s %-20s %-10s %s\n"
                              (or line "?")
                              (truncate-string-to-width (or direction "?") 20)
                              (or sched "?")
                              delay)))))
        (goto-char (point-min))
        (nvvo-departure-mode)
        (setq nvvo--buffer-stop-id stop-id)))
    (pop-to-buffer buf)))

;;; --- Mode-line departure monitor ---

(defcustom nvvo-modeline-stop-id nil
  "Stop ID to monitor in the mode line.
Use `nvvo-search-stop' to find your stop ID.
Example: 33000016"
  :type '(choice (const nil) string)
  :group 'nvvo)

(defcustom nvvo-modeline-walk-time 0
  "Walking time to the stop in minutes.
Departures earlier than this are excluded."
  :type 'integer
  :group 'nvvo)

(defcustom nvvo-modeline-filters nil
  "List of lines to show in mode line.
Each entry is a list of (LINE DIRECTION) where DIRECTION can be
empty to match any direction for that line.
Example: ((\"41\" \"Wölfnitz\") (\"11\" \"\"))"
  :type '(repeat (list (string :tag "Line")
                       (string :tag "Direction (substring, empty=any)")))
  :group 'nvvo)

(defcustom nvvo-modeline-interval 120
  "Refresh interval in seconds for mode-line departures."
  :type 'integer
  :group 'nvvo)

(defvar nvvo--modeline-string nil)
(defvar nvvo--modeline-timer nil)

(defun nvvo--departure-minutes (dep)
  "Return minutes until departure DEP, or nil."
  (when-let* ((time-str (or (alist-get 'RealTime dep)
                            (alist-get 'ScheduledTime dep)))
              (_ (string-match "/Date(\\([0-9]+\\)[+-]" time-str))
              (ms (string-to-number (match-string 1 time-str)))
              (diff (/ (- ms (* (float-time) 1000)) 60000)))
    (max 0 (floor diff))))

(defun nvvo--dep-matches-filter (dep)
  "Return non-nil if DEP matches any entry in `nvvo-modeline-filters'."
  (or (null nvvo-modeline-filters)
      (let ((line (alist-get 'LineName dep))
            (dir  (or (alist-get 'Direction dep) "")))
        (cl-some (lambda (f)
                   (and (equal (nth 0 f) line)
                        (or (string-empty-p (nth 1 f))
                            (string-match-p (regexp-quote (nth 1 f)) dir))))
                 nvvo-modeline-filters))))

(defun nvvo-modeline-debug ()
  "Show all departures from the configured stop to help set up filters."
  (interactive)
  (unless nvvo-modeline-stop-id
    (error "Set `nvvo-modeline-stop-id' first"))
  (let* ((resp (nvvo--fetch-departures nvvo-modeline-stop-id 20))
         (deps (append (alist-get 'Departures resp) nil)))
    (with-current-buffer (get-buffer-create "*VVO Filter Debug*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "Stop: %s, %s (ID: %s)\n"
                        (alist-get 'Name resp) (alist-get 'Place resp) nvvo-modeline-stop-id))
        (insert (format "Current filters: %S\n\n" nvvo-modeline-filters))
        (insert (format "%-6s %-25s %s\n" "Line" "Direction" "Match?"))
        (insert (make-string 50 ?─) "\n")
        (dolist (dep deps)
          (insert (format "%-6s %-25s %s\n"
                          (alist-get 'LineName dep)
                          (alist-get 'Direction dep)
                          (if (nvvo--dep-matches-filter dep) "✓" "✗"))))
        (goto-char (point-min))
        (special-mode))
      (pop-to-buffer (current-buffer)))))

(defun nvvo--modeline-update ()
  "Fetch departures and update the mode-line string."
  (condition-case nil
      (let* ((resp (nvvo--fetch-departures nvvo-modeline-stop-id 40 nvvo-modeline-walk-time))
             (deps (seq-filter #'nvvo--dep-matches-filter
                               (append (alist-get 'Departures resp) nil)))
             (grouped (make-hash-table :test 'equal)))
        ;; group by line+direction
        (dolist (dep deps)
          (let* ((line (alist-get 'LineName dep))
                 (dir  (alist-get 'Direction dep))
                 (key  (cons line dir))
                 (mins (nvvo--departure-minutes dep))
                 (delayed (equal (alist-get 'State dep) "Delayed"))
                 (entry (cons mins delayed)))
            (puthash key (append (gethash key grouped) (list entry)) grouped)))
        ;; build display, sorted by earliest departure
        (let* ((entries nil))
          (maphash (lambda (key times)
                     (push (cons key times) entries))
                   grouped)
          (setq entries (sort entries (lambda (a b)
                                        (< (car (cadr a)) (car (cadr b))))))
          (let ((parts (mapcar (lambda (e)
                                 (let* ((line (caar e))
                                        (dir  (cdar e))
					(times (seq-take (cdr e) 2))
					(time-strs (mapcar (lambda (ts)
							     (let ((s (format "%sm" (car ts))))
							       (if (cdr ts)
                                                                   (propertize s 'face '(:foreground "yellow"))
                                                                 s)))
                                                           times))
                                        (text (format "%s→%s %s"
                                                      line
                                                      (truncate-string-to-width (or dir "?") 10)
                                                      (string-join time-strs ","))))
                                   text))
                               entries)))
            (setq nvvo--modeline-string
                  (if parts
                      (concat " 🚋[" (string-join parts " | ") "] ")
                    " 🚋[--] "))
            (force-mode-line-update t))))
    (error (setq nvvo--modeline-string " 🚋[err] "))))

(define-minor-mode nvvo-modeline-mode
  "Show next VVO departures in the mode line."
  :global t
  (setq nvvo--modeline-string "")
  (or global-mode-string (setq global-mode-string '("")))
  (if nvvo-modeline-mode
      (progn
        (unless nvvo-modeline-stop-id
          (setq nvvo-modeline-mode nil)
          (error "Set `nvvo-modeline-stop-id' first"))
        (or (memq 'nvvo--modeline-string global-mode-string)
            (setq global-mode-string
                  (append global-mode-string '(nvvo--modeline-string))))
        (nvvo--modeline-update)
        (setq nvvo--modeline-timer
              (run-at-time nil nvvo-modeline-interval #'nvvo--modeline-update))
        (message "nvvo-modeline started"))
    (when nvvo--modeline-timer
      (cancel-timer nvvo--modeline-timer)
      (setq nvvo--modeline-timer nil))
    (setq nvvo--modeline-string nil)
    (message "nvvo-modeline stopped")))

(provide 'nvvo)
;;; nvvo.el ends here
