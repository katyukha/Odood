from odoo import fields, models


class OdoodTestTr(models.Model):
    _name = "odood.test.tr"
    _description = "Odood test: translations"

    label = fields.Char(
        string="Odood test label",
        # A link longer than a po file line: gettext breaks it at slashes,
        # while Odoo keeps it whole.
        help="See https://odood.dev/test/translations/regenerate/keeps/odoo/line/wrapping/of/po/files "
             "for details.")
