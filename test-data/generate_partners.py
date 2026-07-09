# generate_partners.py — create N random res.partner records.
#
# N is read from the ODOOD_SCRIPT_PARTNER_COUNT environment variable
# (default 10), so the same script can generate different amounts:
#
#     ODOOD_SCRIPT_PARTNER_COUNT=50 odood script py -d mydb generate_partners.py

import os
import random
import string

count = int(os.environ.get("ODOOD_SCRIPT_PARTNER_COUNT", "10"))

def _rand(n, alphabet=string.ascii_lowercase):
    return "".join(random.choices(alphabet, k=n))

Partner = env["res.partner"]
for _ in range(count):
    Partner.create({
        "name": "Test Partner " + _rand(6, string.ascii_uppercase),
        "email": "%s@example.com" % _rand(8),
        "phone": "+1-555-%04d" % random.randint(0, 9999),
    })

# Persist the new records.
env.cr.commit()

print("Created %d random res.partner records." % count)
