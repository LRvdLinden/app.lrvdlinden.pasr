#!/usr/bin/env python3
"""Elke verwijzing naar pasr_businesses in de SQL van supabase/ moet "on delete cascade" of "on delete set null" zijn,
anders blijft pasr_admin_business_delete (20261128-business-delete.sql) hangen op een vreemde sleutel of laat het wezen
achter. Uitzondering: community_claims.issued_at_business in loyalty-community.sql; die wordt door
20261128-business-delete.sql omgezet naar "on delete set null". Gebruik: python3 supabase/tests/business_delete_fk_check.py"""
import re, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
ok = re.compile(r"on\s+delete\s+(cascade|set\s+null)", re.I)
ref = re.compile(r"references\s+(public\.)?pasr_businesses\s*\(\s*id\s*\)([^,;\n]*)", re.I)
EXCEPTIONS = {("loyalty-community.sql", "issued_at_business")}
bad = []
for f in sorted(root.glob("*.sql")):
    for n, line in enumerate(f.read_text().splitlines(), 1):
        m = ref.search(line)
        if m and not ok.search(m.group(2)) and not any(f.name == e[0] and e[1] in line for e in EXCEPTIONS):
            bad.append(f"{f.name}:{n}: {line.strip()}")
if bad:
    print("Verwijzing naar pasr_businesses zonder cascade of set null:\n  " + "\n  ".join(bad))
    sys.exit(1)
print("Alle verwijzingen naar pasr_businesses zijn cascade of set null.")
