#!/usr/bin/env python3

import re
from pathlib import Path

secret_patterns = [
    (r'password\s*=\s*["\'][^$].*["\']', 'Hardcoded password'),
    (r'api[_-]?key\s*=\s*["\'].*["\']', 'Hardcoded API key'), 
    (r'secret\s*=\s*["\'][^$].*["\']', 'Hardcoded secret'),
    (r'token\s*=\s*["\'][^$].*["\']', 'Hardcoded token'),
    (r'-----BEGIN \w+ KEY-----', 'Private key'),
    (r'["\']pk_[a-zA-Z0-9]{24,}["\']', 'Stripe publishable key'),
    (r'["\']sk_[a-zA-Z0-9]{24,}["\']', 'Stripe secret key'),
]

src_dir = Path('/home/nathan/Projects/rave/services/matrix-bridge/src')
for py_file in src_dir.rglob('*.py'):
    try:
        with open(py_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        for line_num, line in enumerate(lines, 1):
            for pattern, description in secret_patterns:
                matches = re.finditer(pattern, line, re.IGNORECASE)
                for match in matches:
                    if '${' in match.group(0) or 'template' in match.group(0).lower():
                        continue
                    print(f'{py_file.name}:{line_num}: {description}: {match.group(0)[:50]}...')
    except:
        pass