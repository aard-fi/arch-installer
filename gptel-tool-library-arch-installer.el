;;; gptel-tool-library-arch-installer.el --- LLM bindings for Arch installer
;;
;; Author: Bernd Wachter
;;
;; Copyright (c) 2025 Bernd Wachter
;;
;; Keywords: tools
;;
;; COPYRIGHT NOTICE
;;
;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2 of the License, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
;; for more details. http://www.gnu.org/copyleft/gpl.html
;;
;;; Commentary:
;;
;; Ever had the urge to watch an LLM struggle to install Arch Linux? I have
;; good news for you...
;;
;;; Code:

(require 'arch-installer)
(require 'gptel-tool-library)

(defvar gptel-tool-library-arch-installer-tools '()
  "The list of arch installer related tools")

(add-to-list 'gptel-tools
             (gptel-make-tool
              :function #'arch-installer-write-serial
              :name  "write-serial"
              :description "Send raw data to the serial console with the Arch linux installer"
              :args (list '(:name "data"
                                  :type string
                                  :description "The data to send to the arch installer"))
              :category "arch"))

(provide 'gptel-tool-library-arch-installer)
;;; gptel-tool-library-arch-installer.el ends here
