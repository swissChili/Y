;; A major mode for Y

(setq y-font-lock-keywords
      (let* ((x-keywords '("←" "↔" "=" "ret" "if" "else" "elif"))
             (x-keywords-regexp (regexp-opt x-keywords 'words))
             (x-vars-regexp "[\^\\d^\\s]+"))
        `((,x-keywords-regexp . font-lock-keyword-face)
          (,x-vars-regexp . font-lock-function-name-face))))

(define-derived-mode y-mode fundamental-mode "Y mode"
  "Major mode for editing Y programs"
  (setq font-lock-defaults '((y-font-lock-keywords))))

(provide y-mode)
