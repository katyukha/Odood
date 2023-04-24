# Get partner records to check/update
p1 = env['res.partner'].browse(1)
p2 = env['res.partner'].browse(2)

# Check if names of partners were updated by SQL script that was ran before.
assert(p1.name == "Test SQL 72", "Partner 1 was not updated with SQL script")
assert(p2.name == "Test SQL 75", "Partner 1 was not updated with SQL script")

# Update the name of partner 1 and 2 from python script
p1.name = "Test PY 41"
p2.name = "Test PY 42"

# Commit changes
env.cr.commit()
