(require 'ansi-color)

(defcustom arch-installer-serial-device "/dev/ttyS0"
  "Serial device to open.")

(defcustom arch-installer-baud-rate 115200
  "Baud rate for serial communication.")

(defcustom arch-installer-serial-echo nil
  "Echo everything written to the serial console into the output buffer")

(defcustom arch-installer-serial-buffer "*arch-installer*"
  "The output buffer for the serial connection")

(defcustom arch-installer-serial-buffer-plain nil
  "An optional output buffer with font faces stripped. This can be useful if a
specific LLM struggles with the fontified variant")

;;; only internals below

(defvar arch-installer--serial-process nil
  "Process object for the serial device connection.")

(defvar arch-installer--bootmenu-detected nil
  "Whether the Arch Linux boot menu has been detected.")

(defvar arch-installer--waiting-for-bootmenu t
  "Whether we are still waiting for the boot menu prompt.")

(defun arch-installer--strip-ansi-escape-sequences (string)
  "Remove ANSI escape sequences from STRING."
  (replace-regexp-in-string
   "\x1b\\[[0-9;]*[a-zA-Z]" "" string))

(defun arch-installer--strip-terminal-escape-characters (string)
  "Remove common terminal escape/control characters from STRING.

This includes:
- NUL (^@, octal 000)
- Control characters from 0 to 8 octal (includes ^A, ^B, etc.)
- Carriage return (^M, octal 015)
- DEL (^?, octal 177)

This still needs some work for removing all the ones (and only those)
we don't want."
  (replace-regexp-in-string "[\000-\010\013\014\015\016\177]" "" string))

(defun arch-installer--serial-echo (string)
  "Echo STRING into serial output buffer if echo is enabled"
  (when arch-installer-serial-echo
    (with-current-buffer (get-buffer-create arch-installer-serial-buffer)
      (insert string))
    (when arch-installer-serial-buffer-plain
      (with-current-buffer (get-buffer-create arch-installer-serial-buffer-plain)
        (insert string)))))

(defun arch-installer--print-console-input (string)
  "Append STRING to the output buffer.

The default buffer will try to fontify ANSI espace sequences - this may not
always be desired. For those cases `arch-installer-serial-buffer-plain' can be
set to an additional buffer receiving plain text output"
  ;;(setq string (replace-regexp-in-string "" "" string))
  (setq string (arch-installer--strip-terminal-escape-characters string))
  (with-current-buffer (get-buffer-create arch-installer-serial-buffer)
    (font-lock-mode 1)
    (goto-char (point-max))
    (insert (ansi-color-apply string)))
  (when arch-installer-serial-buffer-plain
    (with-current-buffer (get-buffer-create arch-installer-serial-buffer-plain)
      (font-lock-mode 1)
      (goto-char (point-max))
      (insert (arch-installer--strip-ansi-escape-sequences string)))))

(defun arch-installer--serial-process-alive-p (proc device)
  "Return t if PROC is alive and connected to DEVICE."
  (and (process-live-p proc)
       (string= (process-contact proc :local) device)))

(defun arch-installer--process-filter  (proc string)
  "Process filter to echo serial input and intercept the bootloader.

It tries to intercept the bootloader exactly once, to start with serial console
enabled. To restart the detection you can use `arch-installer-reset-state', which
also clears the output buffers."
  (arch-installer--print-console-input string)
  (when (and arch-installer--waiting-for-bootmenu
             (not arch-installer--bootmenu-detected))
    (let ((clean-string (arch-installer--strip-ansi-escape-sequences string)))
      (when (string-match-p "Press \\[Tab\\] to edit options" clean-string)
        (setq arch-installer--bootmenu-detected t)
        (setq arch-installer--waiting-for-bootmenu nil)
        (message "Boot menu prompt detected on serial port.")
        (run-at-time
         1 nil
         (lambda (p)
           (process-send-string p "\t")
           (process-send-string p " console=ttyS0\n")
           (arch-installer--serial-echo " console=ttyS0\n"))
         proc)))))

(defun arch-installer-open-serial (&optional device baud)
  "Open or reuse serial process on DEVICE at BAUD, and start a process filter.

Returns the serial process or signals error if device missing."
  (setq device (or device arch-installer-serial-device))
  (setq baud (or baud arch-installer-baud-rate))
  (if (and arch-installer--serial-process
           (arch-installer--serial-process-alive-p arch-installer--serial-process device))
      arch-installer--serial-process
    (when (and arch-installer--serial-process
               ;; the process exists, but is not connected to the currently set
               ;; device -> terminate, and create a new one later on
               (process-live-p arch-installer--serial-process))
      (delete-process arch-installer--serial-process))
    (unless (file-exists-p device)
      (error "Serial device %s does not exist" device))
    (setq arch-installer--serial-process
          (make-serial-process
           :port device
           :speed baud
           :coding 'utf-8
           :name "arch-installer-process-filter"
           :filter #'arch-installer--process-filter
           :sentinel (lambda (_proc event)
                       (message "Serial process event: %s" event))))
    arch-installer--serial-process))

(defun arch-installer-write-serial (string &optional override-wait)
  "Write STRING to serial process.

If we're still waiting for the boot menu this will throw an error, unless
OVERRIDE-WAIT is non-nil"
  (unless arch-installer--serial-process
    (error "Serial port is not open"))
  (when (and arch-installer--waiting-for-bootmenu (not override-wait))
    (error "Cannot write to serial port: still waiting for boot menu"))
  (process-send-string arch-installer--serial-process string)
  (arch-installer--serial-echo string))

(defun arch-installer-reset-state ()
  "Clear the serial output buffers, and reset variables to defaults."
  (setq arch-installer--bootmenu-detected nil)
  (setq arch-installer--waiting-for-bootmenu t)
  (with-current-buffer arch-installer-serial-buffer
    (when (local-variable-p 'gptel-tool-library-buffer--last-read-pos)
      (setq gptel-tool-library-buffer--last-read-pos (point-min)))
    (erase-buffer))
  (when arch-installer-serial-buffer-plain
    (with-current-buffer arch-installer-serial-buffer-plain
      (when (local-variable-p 'gptel-tool-library-buffer--last-read-pos)
        (setq gptel-tool-library-buffer--last-read-pos (point-min)))
      (erase-buffer))))

(defun arch-installer-insert-default-prompt ()
  "A sample default prompt for starting the installation."
  (interactive)
  (insert "I want you to try to install arch linux. A VM with a serial pty to the arch linux installer (you might have to log in first) is running. All output of that serial port is visible in the *arch-installer* buffer. You can write to the console with the arch-installer-write-serial tool - don't forget to send return/newlines if you want to send a command. Use full or (probably better) partial reads of the status buffer to check progress. Pause and ask me if you get stuck, or need input on how to configure some things. Don't ask questions about things you can figure out by yourself."))

(provide 'arch-installer)
