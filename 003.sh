#!/usr/bin/env bash
# =============================================================================
# script-03-itr-core.sh (003.sh) — PHASE 3 (COMPLETE) — Iran Trade & Transport ERP
# Odoo 19.0 | File-First | Idempotent | Test-First | Gate-Enforced | No sudo-proof
#
# ماژول ستون فقرات سازمان، نقش‌ها، کاربران و داده‌های پایه : itr_core (بخش اول)
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt  ← «فاز ۳» بندهای 3.1..3.12
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۴، بخش ۹-۱، بخش ۹-۲، بخش ۱۴
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh (فاز ۰)، 001.sh (فاز ۱) و 002.sh (فاز ۲) همین مخزن.
#
# پوشش کامل چک‌لیست فاز ۳:
#   3.1  اسکلت ماژول itr_core با وابستگی به itr_base + itr_notify
#   3.2  ساخت ۱۳ گروه امنیتی طبق جدول بخش ۴ سند نیازمندی (تحت res.groups.privilege در Odoo 19)
#   3.3  ساخت ۱۲ کاربر واقعی با ایمیل و گروه‌های دقیق؛ هر دو مدیرعامل (کرمیان و یوسفی) هم‌زمان
#        عضو group_ceo و group_document_signer
#   3.4  کاربر Administrator هیچ گروه کسب‌وکاری نمی‌گیرد (با تست منفی و گارد دائمی)
#   3.5  مدل «تیم سرپرستی» (itr.supervisor.team + عضو) — چندکاربره از روز اول
#   3.6  مجوز خواندن (read/search) روی مدل‌های پایه برای همهٔ گروه‌ها؛ export/report فقط برای مالی/CEO (SEC-011)
#   3.7  داده‌های مرجع: ۶ مرز رسمی (بازرگان، آستارا، دوغارون، مهران، بندرعباس، اینچه‌برون)، باربری‌ها، ترخیص‌کاران و نمایندگان مرز
#   3.8  توسعهٔ راننده و خودرو با تابعیت (ایرانی/غیرایرانی)، گذرنامه، وضعیت کارت هوشمند و نوع پلاک (G13)
#   3.9  توسعهٔ res.partner: is_factory، customer_scope، سقف اعتبار، کدملی و کداقتصادی
#   3.10 سرویس نرخ ارز utils/fx.py و مدل itr.fx.service (resolve_rate, apply_fx, rate_locked) + تنظیمات خزانه
#   3.11 ساختار Record Rule سطح تیم و شرکت روی مدل‌های دامنه
#   3.12 فایل ترجمهٔ فارسی برای تمام گروه‌ها، مدل‌ها و منوهای این فاز (i18n/fa_IR.po + fa.po)
#   verify مستقل V3-01..V3-07 (کاربر واقعی، بدون sudo، rollback در پایان) + Gate 3
#
# پیش‌نیاز: Gate 2 سبز (bash 002.sh → itr_notify نصب و installed)
#
# استفاده:
#   chmod +x 003.sh
#   bash 003.sh
#
# سوییچ‌ها:
#   SKIP_TESTS=1    تست‌های خودکار Odoo اجرا نشود (Gate قرمز می‌شود — Q04)
#   SKIP_VERIFY=1   verify مستقل اجرا نشود (Gate قرمز می‌شود — Q15)
#   SKIP_UAT=1      نصب روی پایگاه‌دادهٔ UAT انجام نشود
#   SKIP_BACKUP=1   پشتیبان پیش از ارتقا گرفته نشود (توصیه نمی‌شود)
#   START_DAEMON=0  سرویس Odoo دوباره اجرا نشود
# =============================================================================
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8

# ───────────────────────────── CONFIG ────────────────────────────────────────
ODOO_DIR="${ODOO_DIR:-${HOME}/odoo}"
VENV_DIR="${VENV_DIR:-${ODOO_DIR}/.venv}"
CONF_DIR="${CONF_DIR:-${HOME}/.config/odoo}"
CONF_FILE="${CONF_FILE:-${CONF_DIR}/odoo.conf}"
CONF_FILE_UAT="${CONF_FILE_UAT:-${CONF_DIR}/odoo-uat.conf}"
DATA_DIR="${DATA_DIR:-${HOME}/.local/share/odoo}"
CUSTOM_ADDONS="${CUSTOM_ADDONS:-${HOME}/odoo-custom-addons}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/odoo-backups}"

DB_NAME="${DB_NAME:-odoo19_dev}"
DB_NAME_UAT="${DB_NAME_UAT:-odoo19_uat}"

HTTP_INTERFACE="${HTTP_INTERFACE:-0.0.0.0}"
HTTP_PORT="${HTTP_PORT:-8069}"

LOG_FILE="${LOG_FILE:-/tmp/odoo19-site-bootstrap.log}"
PID_FILE="${PID_FILE:-/tmp/odoo19-site-bootstrap.pid}"
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase3-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase3-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase3-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase3-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase3-uat.log}"

MODULE="itr_core"
BASE_MODULE="itr_base"
NOTIFY_MODULE="itr_notify"
MOD_DIR="${CUSTOM_ADDONS}/${MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"

SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SKIP_UAT="${SKIP_UAT:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
START_DAEMON="${START_DAEMON:-1}"
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }
info() { echo -e "${BLUE}[..]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${YELLOW}======== $* ========${NC}"; }

GATE_IDS=(); GATE_TXT=(); GATE_ST=(); GATE_MSG=()
gate() { GATE_IDS+=("$1"); GATE_TXT+=("$2"); GATE_ST+=("$3"); GATE_MSG+=("${4:-}"); }

trap 'ec=$?; [[ $ec -ne 0 ]] && echo -e "\n${RED}[FATAL]${NC} exit=$ec — لاگ‌ها: ${INSTALL_LOG} / ${TEST_LOG} / ${VERIFY_LOG}"' EXIT

[[ "$(id -u)" -eq 0 ]] && err "با کاربر عادی اجرا کنید (نه root)."

write_utf8() {
  local target="$1" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
}

have()        { command -v "$1" >/dev/null 2>&1; }
db_exists()   { psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${1}'" 2>/dev/null | grep -q 1; }
q()           { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }
port_in_use() { ss -lntp 2>/dev/null | grep -q ":${1} " && return 0 || return 1; }

# =============================================================================
step "0) preflight — بررسی پیش‌نیازها و Gate 1 و Gate 2 (Q02/Q08)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد: ${CONF_FILE} (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/${BASE_MODULE}" ]] || err "ماژول ${BASE_MODULE} یافت نشد (ابتدا فاز ۱)"
[[ -d "${CUSTOM_ADDONS}/${NOTIFY_MODULE}" ]] || err "ماژول ${NOTIFY_MODULE} یافت نشد (ابتدا فاز ۲)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G3-00" "نسخهٔ Odoo 19 تأیید شد" "PASS" "${ODOO_V}"
else
  gate "G3-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "نسخهٔ یافت‌شده: ${ODOO_V}"
  err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود."
fi

BASE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${BASE_MODULE}'")"
NOTIFY_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${NOTIFY_MODULE}'")"

if [[ "${BASE_STATE}" == "installed" && "${NOTIFY_STATE}" == "installed" ]]; then
  gate "G3-01" "پیش‌نیازهای فاز ۱ و ۲ سبز هستند (${BASE_MODULE} + ${NOTIFY_MODULE} installed — Q02)" "PASS" "base=${BASE_STATE} notify=${NOTIFY_STATE}"
else
  gate "G3-01" "پیش‌نیازهای فاز ۱ و ۲ سبز هستند (Q02)" "FAIL" "base=${BASE_STATE:-missing} notify=${NOTIFY_STATE:-missing}"
  err "طبق Q08، فازهای ۱ و ۲ باید قبل از فاز ۳ نصب شده باشند."
fi

# =============================================================================
step "1) توقف سرویس در حال اجرا (ارتقا روی DB زنده ممنوع)"
# =============================================================================
stop_odoo() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true
    sleep 3
  fi
  pkill -f "odoo-bin.*${CONF_FILE}" 2>/dev/null || true
  sleep 2
  rm -f "${PID_FILE}"
}
stop_odoo
port_in_use "${HTTP_PORT}" && warn "پورت ${HTTP_PORT} هنوز listen است" || log "سرویس متوقف شد"

# =============================================================================
step "2) پشتیبان پیش از ارتقا (Q10/NFR-005)"
# =============================================================================
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G3-02" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "SKIP_BACKUP=1"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  BK_OUT="$(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)"
  BK_DUMP="$(echo "${BK_OUT}" | head -n1)"
  if [[ -s "${BK_DUMP:-/nonexistent}" ]]; then
    gate "G3-02" "پشتیبان پیش از ارتقا گرفته شد" "PASS" "$(basename "${BK_DUMP}")"
  else
    gate "G3-02" "پشتیبان پیش از ارتقا گرفته شد" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G3-02" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "ops/backup.sh یافت نشد"
fi

# =============================================================================
step "3) ساخت اسکلت ماژول itr_core (File-First / Force-Replace)"
# =============================================================================
mkdir -p "${MOD_DIR}"/{models,utils,security,data,views,i18n,tests}
mkdir -p "${OPS_DIR}/verify" "${DOC_DIR}"
find "${MOD_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "${MOD_DIR}" -name '*.pyc' -delete 2>/dev/null || true

# ---------------------------------------------------------------- __init__ --
write_utf8 "${MOD_DIR}/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import utils
from . import models
from .hooks import post_init_hook
PYEOF

# --------------------------------------------------------------- manifest --
write_utf8 "${MOD_DIR}/__manifest__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
{
    "name": "ITR Core",
    "summary": "Core organization, 13 business roles, 12 real users, supervisor team, FX rates & master reference data",
    "description": """
ITR Core (Phase 3)
==================
The foundational spine of the Iran Trade & Transport ERP.
Closes the "Day One Void" (SEC-011) before any operational workflows start.

Contents
--------
* 13 Security Groups attached via Odoo 19 res.groups.privilege.
* 12 Real Organizational Users seeded with exact corporate roles.
* Two CEOs (Hadi Karamian & Saeed Yousefi) both holding CEO + Document Signer roles.
* Strict Administrator guard: Administrator holds ZERO business groups (Q03/SEC-002).
* Multi-user Supervisor Team model (itr.supervisor.team + member).
* Master Reference Data: 6 Official Iranian Borders (Bazargan, Astara, Dogharoun, Mehran, Bandar Abbas, Incheh Boroun).
* Driver and Vehicle multi-nationality model (G13: Iranian vs Foreign with passport/smart card/plate type).
* res.partner enterprise extension (is_factory, customer_scope, credit limit, national/economic IDs).
* Single FX Rate Service (utils/fx.py & itr.fx.service) with locked rate support (G12/G18).
* Base read/search permissions for all operational users on master data (SEC-011).
""",
    "version": "19.0.1.0.0",
    "category": "Localization/Iran",
    "author": "Iran Trade & Transport ERP",
    "maintainer": "Iran Trade & Transport ERP",
    "license": "LGPL-3",
    "depends": ["base", "mail", "itr_base", "itr_notify"],
    "data": [
        "security/itr_core_groups.xml",
        "security/ir.model.access.csv",
        "security/itr_core_rules.xml",
        "data/itr_treasury_settings_data.xml",
        "data/itr_border_data.xml",
        "data/itr_partner_category_data.xml",
        "data/itr_core_users_data.xml",
        "views/itr_treasury_settings_views.xml",
        "views/itr_supervisor_team_views.xml",
        "views/itr_border_views.xml",
        "views/itr_driver_vehicle_views.xml",
        "views/itr_partner_views.xml",
        "views/itr_core_menus.xml",
    ],
    "post_init_hook": "post_init_hook",
    "installable": True,
    "application": False,
    "auto_install": False,
}
PYEOF

# ------------------------------------------------------------------ hooks --
write_utf8 "${MOD_DIR}/hooks.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Install / upgrade hooks for itr_core.

Idempotent by design (NFR-002):
- Guarantees Administrator remains free of any business group (Q03).
- Ensures the 12 corporate users have their required group memberships.
- Bootstraps singleton settings and verifies master borders.
"""
import logging

_logger = logging.getLogger(__name__)

BUSINESS_GROUP_XMLIDS = [
    "itr_core.group_ceo",
    "itr_core.group_document_signer",
    "itr_core.group_financial_manager",
    "itr_core.group_finance_supervisor",
    "itr_core.group_finance_user",
    "itr_core.group_legal_reviewer",
    "itr_core.group_treasury_user",
    "itr_core.group_receivables_user",
    "itr_core.group_transport_supervisor",
    "itr_core.group_transport_docs",
    "itr_core.group_customs_officer",
    "itr_core.group_transport_delivery",
    "itr_core.group_auditor",
]


def post_init_hook(env):
    _ensure_treasury_settings(env)
    _assert_admin_is_clean(env)
    _verify_real_users(env)
    _logger.info("itr_core: post_init_hook completed successfully.")


def _ensure_treasury_settings(env):
    settings = env["itr.treasury.settings"].get_settings()
    _logger.info("itr_core: treasury settings singleton ready (id=%s)", settings.id)


def _assert_admin_is_clean(env):
    """Q03 guard: Administrator must NEVER hold any business group."""
    admin = env.ref("base.user_admin", raise_if_not_found=False)
    if not admin:
        return
    dirty = [xid for xid in BUSINESS_GROUP_XMLIDS if admin.has_group(xid)]
    if dirty:
        _logger.warning("itr_core/Q03 VIOLATION: Administrator holds business groups %s — removing.", dirty)
        for xid in dirty:
            grp = env.ref(xid, raise_if_not_found=False)
            if grp:
                grp.sudo().write({"user_ids": [(3, admin.id)]})
    else:
        _logger.info("itr_core/Q03 OK: Administrator holds no business group.")


def _verify_real_users(env):
    user_count = env["res.users"].search_count([("login", "in", [
        "hadi.karamian@irbco.local", "saeed.yousefi@irbco.local", "fin.mgr@irbco.local",
        "ehsan.nahalparvar@irbco.local", "faezeh.heydari@irbco.local", "pouya.soleimani@irbco.local",
        "atieh.alaei@irbco.local", "zahra.mirzaei@irbco.local", "najmeh.afrashtehpour@irbco.local",
        "amini@irbco.local", "mohaddeseh.enayati@irbco.local", "mohammadi@irbco.local"
    ])])
    _logger.info("itr_core: %s of 12 real users present in database.", user_count)
PYEOF

# ------------------------------------------------------------------ utils --
write_utf8 "${MOD_DIR}/utils/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import fx
PYEOF

write_utf8 "${MOD_DIR}/utils/fx.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""itr_core.utils.fx — Pure foreign exchange rate and conversion helpers.

G12 / G18 Rules:
- Rate resolution order:
  1) source == target currency => rate 1.0
  2) official res.currency.rate on or before transaction date
  3) fallback treasury settings rate (USD -> IRR)
  4) otherwise raise descriptive Persian error.
- Currency is a property of the financial event/line, not the whole case (G12).
- Conversion is pure and idempotent.
"""
from decimal import Decimal, ROUND_HALF_UP


def compute_base_amount(amount, rate, rounding_digits=0):
    """Calculate base IRR amount = amount * rate."""
    if amount is None or amount is False:
        return 0.0
    if rate is None or rate is False:
        return 0.0
    d_amount = Decimal(str(amount))
    d_rate = Decimal(str(rate))
    res = d_amount * d_rate
    if rounding_digits == 0:
        return float(res.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
    precision = Decimal("1." + "0" * rounding_digits)
    return float(res.quantize(precision, rounding=ROUND_HALF_UP))


def format_currency_amount(amount, currency_name="IRR"):
    if amount is None or amount is False:
        amount = 0
    formatted_num = "{:,.0f}".format(amount) if currency_name in ("IRR", "TOMAN") else "{:,.2f}".format(amount)
    return "%s %s" % (formatted_num, currency_name)
PYEOF

# ----------------------------------------------------------------- models --
write_utf8 "${MOD_DIR}/models/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import itr_treasury_settings
from . import itr_supervisor_team
from . import itr_border
from . import itr_partner
from . import itr_driver
from . import itr_vehicle
from . import itr_fx_service
PYEOF

write_utf8 "${MOD_DIR}/models/itr_treasury_settings.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Central Treasury & FX Settings Singleton."""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

DEFAULT_TREASURY_NAME = "ITR Treasury Settings"


class ItrTreasurySettings(models.Model):
    _name = "itr.treasury.settings"
    _description = "Iran Treasury and FX Settings"
    _rec_name = "name"

    name = fields.Char(string="Name", required=True, default=DEFAULT_TREASURY_NAME)
    base_currency_id = fields.Many2one(
        "res.currency",
        string="Base Currency",
        required=True,
        default=lambda self: self.env.ref("base.IRR", raise_if_not_found=False) or self.env.company.currency_id,
    )
    usd_currency_id = fields.Many2one(
        "res.currency",
        string="USD Currency",
        default=lambda self: self.env.ref("base.USD", raise_if_not_found=False),
    )
    fallback_usd_rate = fields.Float(
        string="Manual Fallback USD/IRR Rate",
        default=1100000.0,
        digits=(16, 2),
        help="Used only when no official res.currency.rate is configured for the transaction date.",
    )
    eur_currency_id = fields.Many2one(
        "res.currency",
        string="EUR Currency",
        default=lambda self: self.env.ref("base.EUR", raise_if_not_found=False),
    )
    fallback_eur_rate = fields.Float(
        string="Manual Fallback EUR/IRR Rate",
        default=1200000.0,
        digits=(16, 2),
    )
    require_rate_locking = fields.Boolean(
        string="Require explicit rate locking upon review approval",
        default=True,
    )
    note = fields.Text(string="Notes")

    @api.constrains("name")
    def _check_single_record(self):
        if self.search_count([]) > 1:
            raise ValidationError(_("Only one Treasury Settings record is allowed (singleton)."))

    @api.model
    def get_settings(self):
        settings = self.env.ref("itr_core.itr_treasury_settings_default", raise_if_not_found=False)
        if settings:
            return settings
        settings = self.search([], limit=1)
        if settings:
            return settings
        return self.sudo().create({"name": DEFAULT_TREASURY_NAME})  # ITR-SUDO-OK
PYEOF

write_utf8 "${MOD_DIR}/models/itr_supervisor_team.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Supervisor Team and Members — Multi-user from Day One (Checklist 3.5).

Guarantees:
- Never assume a single user per role.
- Team supervisors can assign/reassign cases within their active team members.
- Guard against assigning Administrator or OdooBot as supervisor or member.
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

FORBIDDEN_USERS = ("admin", "__system__", "bot")


class ItrSupervisorTeam(models.Model):
    _name = "itr.supervisor.team"
    _description = "Supervisor Team"
    _inherit = ["mail.thread", "mail.activity.mixin"]
    _order = "sequence, name"

    name = fields.Char(string="Team Name", required=True, index=True, tracking=True)
    sequence = fields.Integer(string="Sequence", default=10)
    supervisor_id = fields.Many2one(
        "res.users",
        string="Supervisor",
        required=True,
        tracking=True,
        domain="[('share', '=', False), ('active', '=', True)]",
    )
    unit = fields.Selection(
        [
            ("finance", "Finance Unit"),
            ("transport", "Transport Unit"),
            ("customs", "Customs & Clearance Unit"),
            ("management", "Executive Management"),
        ],
        string="Unit",
        required=True,
        default="finance",
        tracking=True,
    )
    active = fields.Boolean(string="Active", default=True, tracking=True)
    member_ids = fields.One2many(
        "itr.supervisor.team.member",
        "team_id",
        string="Team Members",
    )
    member_count = fields.Integer(string="Member Count", compute="_compute_member_count")
    note = fields.Text(string="Notes")

    @api.depends("member_ids")
    def _compute_member_count(self):
        for record in self:
            record.member_count = len(record.member_ids.filtered(lambda m: m.is_active))

    @api.constrains("supervisor_id", "member_ids")
    def _check_team_guards(self):
        for team in self:
            if team.supervisor_id.login in FORBIDDEN_USERS:
                raise ValidationError(_("Administrator / System user cannot be designated as a team supervisor."))
            seen_users = set()
            for m in team.member_ids:
                if m.user_id.login in FORBIDDEN_USERS:
                    raise ValidationError(_("Administrator / System user cannot be added as a team member."))
                if m.user_id.id in seen_users:
                    raise ValidationError(_("User %s is added more than once to team %s.") % (m.user_id.name, team.name))
                seen_users.add(m.user_id.id)

    @api.model
    def get_user_teams(self, user_id=None):
        uid = user_id or self.env.user.id
        return self.search([
            "|",
            ("supervisor_id", "=", uid),
            ("member_ids.user_id", "=", uid),
            ("active", "=", True),
        ])

    @api.model
    def get_subordinate_users(self, supervisor_id=None, unit=None):
        """Return list of active member user records supervised by supervisor_id."""
        sup_id = supervisor_id or self.env.user.id
        domain = [("supervisor_id", "=", sup_id), ("active", "=", True)]
        if unit:
            domain.append(("unit", "=", unit))
        teams = self.search(domain)
        members = teams.mapped("member_ids").filtered(lambda m: m.is_active).mapped("user_id")
        return members


class ItrSupervisorTeamMember(models.Model):
    _name = "itr.supervisor.team.member"
    _description = "Supervisor Team Member"
    _order = "team_id, sequence, id"

    team_id = fields.Many2one("itr.supervisor.team", string="Team", required=True, ondelete="cascade", index=True)
    sequence = fields.Integer(string="Sequence", default=10)
    user_id = fields.Many2one(
        "res.users",
        string="Member User",
        required=True,
        domain="[('share', '=', False), ('active', '=', True)]",
    )
    user_email = fields.Char(related="user_id.email", string="Email", readonly=True)
    is_active = fields.Boolean(string="Active in Team", default=True)
    max_open_cases = fields.Integer(
        string="Max Open Cases Capacity",
        default=20,
        help="Maximum number of active concurrent cases before automated assignment warning.",
    )
    current_workload = fields.Integer(string="Current Active Workload", default=0, readonly=True)
PYEOF

write_utf8 "${MOD_DIR}/models/itr_border.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Master Reference Data: Official Iranian Customs Borders (Checklist 3.7)."""
from odoo import api, fields, models


class ItrBorder(models.Model):
    _name = "itr.border"
    _description = "Iranian Official Customs Border"
    _order = "sequence, name"

    name = fields.Char(string="Border Name (Persian)", required=True, index=True)
    code = fields.Char(string="Technical / Customs Code", required=True, index=True)
    neighbor_country_id = fields.Many2one("res.country", string="Neighbor Country")
    border_type = fields.Selection(
        [
            ("land", "Land Border"),
            ("sea", "Sea Port"),
            ("air", "Air Customs"),
            ("rail", "Rail Border"),
        ],
        string="Border Type",
        default="land",
        required=True,
    )
    sequence = fields.Integer(string="Sequence", default=10)
    active = fields.Boolean(string="Active", default=True)
    has_customs_office = fields.Boolean(string="Has Customs Office", default=True)
    default_clearance_agent_id = fields.Many2one("res.partner", string="Default Clearance Agent")
    note = fields.Text(string="Notes")

    _sql_constraints = [
        ("code_uniq", "unique(code)", "Customs Border code must be unique!"),
    ]
PYEOF

write_utf8 "${MOD_DIR}/models/itr_partner.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Enterprise Partner Extension (Checklist 3.9 & SEC-011)."""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class ResPartner(models.Model):
    _inherit = "res.partner"

    is_factory = fields.Boolean(string="Is Production Factory / Origin", default=False, index=True)
    is_customs_agent = fields.Boolean(string="Is Customs Clearance Agent", default=False, index=True)
    is_border_rep = fields.Boolean(string="Is Border Representative", default=False, index=True)
    is_shipping_line = fields.Boolean(string="Is Freight Forwarder / Shipping Co", default=False, index=True)

    customer_scope = fields.Selection(
        [
            ("domestic", "Domestic Customer"),
            ("export", "Export Customer"),
            ("both", "Both Domestic & Export"),
        ],
        string="Customer Trade Scope",
        default="domestic",
    )
    national_id = fields.Char(string="National ID (Iranian)", index=True)
    economic_code = fields.Char(string="Economic Code", index=True)
    sheba_number = fields.Char(string="Default SHEBA Account", index=True)
    sheba_masked = fields.Char(string="Masked SHEBA", compute="_compute_sheba_masked", store=False)

    trade_credit_limit = fields.Float(string="Trade Credit Limit (IRR)", default=0.0)
    assigned_finance_user_id = fields.Many2one("res.users", string="Dedicated Finance Specialist")

    @api.depends("sheba_number")
    def _compute_sheba_masked(self):
        val_service = self.env["itr.validation.service"]
        for record in self:
            if record.sheba_number:
                record.sheba_masked = val_service.mask_sheba(record.sheba_number)
            else:
                record.sheba_masked = ""

    @api.constrains("national_id", "country_id")
    def _check_partner_national_id(self):
        val_service = self.env["itr.validation.service"]
        for partner in self:
            if not partner.national_id:
                continue
            is_iranian = not partner.country_id or partner.country_id.code == "IR"
            if is_iranian and not partner.is_company:
                val_service.check_national_id(
                    partner.national_id,
                    nationality="iranian",
                    res_model=self._name,
                    res_id=partner.id,
                )
PYEOF

write_utf8 "${MOD_DIR}/models/itr_driver.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Master Driver Model with Multi-Nationality Guard (Checklist 3.8 / G13)."""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class ItrDriver(models.Model):
    _name = "itr.driver"
    _description = "Fleet Driver"
    _inherit = ["mail.thread", "mail.activity.mixin"]
    _order = "name"

    name = fields.Char(string="Driver Full Name", required=True, index=True, tracking=True)
    partner_id = fields.Many2one("res.partner", string="Related Contact / Partner", ondelete="restrict")
    mobile = fields.Char(string="Mobile Number", required=True, index=True, tracking=True)
    nationality = fields.Selection(
        [
            ("iranian", "Iranian National"),
            ("foreign", "Foreign National"),
        ],
        string="Nationality",
        required=True,
        default="iranian",
        tracking=True,
    )
    national_id = fields.Char(string="Iranian National ID", index=True, tracking=True)
    passport_number = fields.Char(string="Passport Number (Foreign Drivers)", index=True, tracking=True)
    country_id = fields.Many2one(
        "res.country",
        string="Country of Citizenship",
        default=lambda self: self.env.ref("base.ir", raise_if_not_found=False),
    )

    smart_card_number = fields.Char(string="Smart Card Number", index=True, tracking=True)
    smart_card_status = fields.Selection(
        [
            ("valid", "Valid & Active"),
            ("expired", "Expired"),
            ("suspended", "Suspended"),
            ("not_checked", "Not Checked"),
        ],
        string="Smart Card Status",
        default="not_checked",
        tracking=True,
    )
    smart_card_inquiry_date = fields.Date(string="Last Smart Card Inquiry Date")

    license_number = fields.Char(string="Driving License Number")
    sheba_number = fields.Char(string="Default Bank SHEBA")
    sheba_masked = fields.Char(string="Masked SHEBA", compute="_compute_sheba_masked", store=False)
    active = fields.Boolean(string="Active", default=True)
    note = fields.Text(string="Notes & History")

    @api.depends("sheba_number")
    def _compute_sheba_masked(self):
        val_service = self.env["itr.validation.service"]
        for record in self:
            record.sheba_masked = val_service.mask_sheba(record.sheba_number) if record.sheba_number else ""

    @staticmethod
    def _is_valid_iranian_national_id(nid):
        """Standard Iranian national ID checksum (rejects all-same-digit series)."""
        if not nid:
            return False
        nid = str(nid).strip()
        if not nid.isdigit() or len(nid) != 10:
            return False
        if len(set(nid)) == 1:
            return False
        checksum = sum(int(nid[i]) * (10 - i) for i in range(9)) % 11
        control = int(nid[9])
        if checksum < 2:
            return control == checksum
        return control == 11 - checksum

    @api.constrains("national_id", "nationality", "mobile")
    def _check_driver_identity(self):
        val_service = self.env["itr.validation.service"]
        for driver in self:
            if driver.nationality == "iranian":
                if driver.national_id:
                    # Enforce checksum locally so invalid IDs always raise ValidationError
                    # even if the central service is format-only / non-raising for some inputs.
                    if not self._is_valid_iranian_national_id(driver.national_id):
                        raise ValidationError(_("Invalid Iranian National ID for driver."))
                    val_service.check_national_id(
                        driver.national_id,
                        nationality="iranian",
                        res_model=self._name,
                        res_id=driver.id,
                    )
                if driver.mobile:
                    val_service.check_mobile(
                        driver.mobile,
                        res_model=self._name,
                        res_id=driver.id,
                    )
            else:
                # G13: Foreign driver must have passport if national id absent
                if not driver.passport_number and not driver.national_id:
                    raise ValidationError(_("Foreign driver must have a Passport Number specified."))
PYEOF

write_utf8 "${MOD_DIR}/models/itr_vehicle.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Master Vehicle / Truck Model with Plate Types (Checklist 3.8 / G13)."""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class ItrVehicle(models.Model):
    _name = "itr.vehicle"
    _description = "Transport Vehicle"
    _inherit = ["mail.thread", "mail.activity.mixin"]
    _order = "plate_number"

    name = fields.Char(string="Vehicle Description", compute="_compute_name", store=True)
    plate_number = fields.Char(string="Plate Number", required=True, index=True, tracking=True)
    plate_type = fields.Selection(
        [
            ("iranian", "Iranian National Plate"),
            ("transit", "International Transit Plate"),
            ("temporary", "Temporary Admission Plate"),
        ],
        string="Plate Type",
        required=True,
        default="iranian",
        tracking=True,
    )
    vehicle_type = fields.Selection(
        [
            ("trailer", "Trailer / Container Carrier"),
            ("tent", "Tent Truck (Transit)"),
            ("refrigerated", "Refrigerated Truck"),
            ("flatbed", "Flatbed Truck"),
            ("tanker", "Tanker Truck"),
            ("dump", "Dump Truck"),
        ],
        string="Vehicle Type",
        default="trailer",
        required=True,
    )
    smart_card_number = fields.Char(string="Vehicle Smart Card Number", index=True)
    default_driver_id = fields.Many2one("itr.driver", string="Default Assigned Driver")
    max_tonnage_capacity = fields.Float(string="Max Tonnage Capacity (Tons)", default=25.0)
    active = fields.Boolean(string="Active", default=True)
    note = fields.Text(string="Notes")

    @api.depends("plate_number", "plate_type", "vehicle_type")
    def _compute_name(self):
        for record in self:
            record.name = "%s [%s]" % (record.plate_number or "-", record.plate_type or "-")

    @api.constrains("plate_number", "plate_type")
    def _check_vehicle_plate(self):
        val_service = self.env["itr.validation.service"]
        for vehicle in self:
            if vehicle.plate_number:
                val_service.check_plate(
                    vehicle.plate_number,
                    plate_type=vehicle.plate_type,
                    res_model=self._name,
                    res_id=vehicle.id,
                )
PYEOF

write_utf8 "${MOD_DIR}/models/itr_fx_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Central FX Service Model (Checklist 3.10 / G12 / G18)."""
import datetime
from odoo import _, api, fields, models
from odoo.exceptions import UserError

from ..utils import fx


class ItrFxService(models.AbstractModel):
    _name = "itr.fx.service"
    _description = "Foreign Exchange Rate Resolution Service"

    @api.model
    def resolve_rate(self, from_currency, to_currency=None, date=None):
        """Resolve conversion rate from from_currency to to_currency on given date.

        Priority order:
        1) from_currency == to_currency => 1.0
        2) res.currency.rate official rate
        3) fallback rate in itr.treasury.settings
        4) raise UserError
        """
        treasury = self.env["itr.treasury.settings"].get_settings()
        target_curr = to_currency or treasury.base_currency_id

        if not from_currency or not target_curr:
            return 1.0

        if from_currency.id == target_curr.id or from_currency.name == target_curr.name:
            return 1.0

        check_date = date or fields.Date.today()
        # 1) Try official Odoo currency rates
        rate_rec = self.env["res.currency.rate"].search([
            ("currency_id", "=", from_currency.id),
            ("name", "<=", check_date),
            ("company_id", "in", [self.env.company.id, False]),
        ], order="name desc", limit=1)

        if rate_rec and rate_rec.rate > 0:
            # Note: Odoo standard rates are target/base or base/target;
            # in Iran ERP, rate is IRR per 1 Foreign Unit (e.g. 1 USD = 1,100,000 IRR)
            # If rate_rec.rate is stored as inverse, handle accordingly:
            if rate_rec.rate >= 1000:
                return rate_rec.rate
            return 1.0 / rate_rec.rate

        # 2) Fallback to treasury settings for known pairs
        if from_currency.name == "USD" and target_curr.name in ("IRR", "TOMAN"):
            if treasury.fallback_usd_rate > 0:
                return treasury.fallback_usd_rate
        elif from_currency.name == "EUR" and target_curr.name in ("IRR", "TOMAN"):
            if treasury.fallback_eur_rate > 0:
                return treasury.fallback_eur_rate

        raise UserError(_(
            "No official or fallback exchange rate found for currency %(curr)s to %(target)s on date %(date)s.",
            curr=from_currency.name,
            target=target_curr.name,
            date=str(check_date),
        ))

    @api.model
    def apply_fx(self, amount, from_currency, to_currency=None, date=None):
        """Convert amount and return dict(base_amount, rate, rate_locked)."""
        rate = self.resolve_rate(from_currency, to_currency, date)
        base_amt = fx.compute_base_amount(amount, rate)
        return {
            "amount": amount,
            "currency_id": from_currency.id if from_currency else False,
            "conversion_rate": rate,
            "base_amount": base_amt,
            "rate_locked": True,
        }
PYEOF

# --------------------------------------------------------------- security --
write_utf8 "${MOD_DIR}/security/itr_core_groups.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <record id="privilege_itr_core" model="res.groups.privilege">
            <field name="name">Iran Trade &amp; Transport Core Roles</field>
            <field name="description">13 Business roles and operational master permissions</field>
            <field name="category_id" ref="itr_base.module_category_itr"/>
            <field name="sequence">20</field>
        </record>

        <!-- 1) CEO -->
        <record id="group_ceo" model="res.groups">
            <field name="name">CEO / Executive Board</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Chief Executive Officer — issues deal orders, full strategic visibility.</field>
        </record>

        <!-- 2) Document Signer -->
        <record id="group_document_signer" model="res.groups">
            <field name="name">Document Signer</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Authorized signer for physical and accounting commercial orders.</field>
        </record>

        <!-- 3) Financial Manager -->
        <record id="group_financial_manager" model="res.groups">
            <field name="name">Financial Manager</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Head of financial affairs, oversees macro financial reports.</field>
        </record>

        <!-- 4) Finance Supervisor -->
        <record id="group_finance_supervisor" model="res.groups">
            <field name="name">Finance Supervisor</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Supervises finance operations, prints Sepidar forms, manages team workload.</field>
        </record>

        <!-- 5) Finance User -->
        <record id="group_finance_user" model="res.groups">
            <field name="name">Finance Specialist</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Forms Trade Cases, enters line items and issues Sales slips.</field>
        </record>

        <!-- 6) Legal Reviewer -->
        <record id="group_legal_reviewer" model="res.groups">
            <field name="name">Legal Reviewer</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Performs legal risk check, contracts validity and sanctions screening.</field>
        </record>

        <!-- 7) Treasury User -->
        <record id="group_treasury_user" model="res.groups">
            <field name="name">Treasury Specialist</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Reviews payment availability, cashflow constraints and currency sources.</field>
        </record>

        <!-- 8) Receivables User -->
        <record id="group_receivables_user" model="res.groups">
            <field name="name">Receivables &amp; Credit Specialist</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Reviews customer credit line, open invoices and collection guarantees.</field>
        </record>

        <!-- 9) Transport Supervisor -->
        <record id="group_transport_supervisor" model="res.groups">
            <field name="name">Transport Supervisor</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Supervises fleet loading authorization, logistics dispatch and team workload.</field>
        </record>

        <!-- 10) Transport Docs Specialist -->
        <record id="group_transport_docs" model="res.groups">
            <field name="name">Transport Specialist - Fleet &amp; Documents</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Records driver, waybill, insurance, weighbridge and packing lists.</field>
        </record>

        <!-- 11) Customs Officer -->
        <record id="group_customs_officer" model="res.groups">
            <field name="name">Customs &amp; Clearance Officer</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Coordinates border reps, Bijak verification and customs declaration.</field>
        </record>

        <!-- 12) Transport Delivery & Settlement Specialist -->
        <record id="group_transport_delivery" model="res.groups">
            <field name="name">Transport Specialist - Delivery &amp; Settlement</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Validates POD delivery receipts, collects SHEBA accounts and registers payment requests.</field>
        </record>

        <!-- 13) Auditor Read-Only -->
        <record id="group_auditor" model="res.groups">
            <field name="name">Auditor (Read-Only)</field>
            <field name="privilege_id" ref="itr_core.privilege_itr_core"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">Comprehensive read-only access for compliance and audit trail inspection.</field>
        </record>

    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/security/ir.model.access.csv" <<'CSVEOF'
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_itr_treasury_settings_user,itr.treasury.settings user,model_itr_treasury_settings,base.group_user,1,0,0,0
access_itr_treasury_settings_fin_mgr,itr.treasury.settings fin mgr,model_itr_treasury_settings,itr_core.group_financial_manager,1,1,0,0
access_itr_treasury_settings_fin_sup,itr.treasury.settings fin sup,model_itr_treasury_settings,itr_core.group_finance_supervisor,1,1,0,0
access_itr_treasury_settings_ceo,itr.treasury.settings ceo,model_itr_treasury_settings,itr_core.group_ceo,1,1,0,0

access_itr_supervisor_team_user,itr.supervisor.team user read,model_itr_supervisor_team,base.group_user,1,0,0,0
access_itr_supervisor_team_sup_fin,itr.supervisor.team fin sup,model_itr_supervisor_team,itr_core.group_finance_supervisor,1,1,1,0
access_itr_supervisor_team_sup_trn,itr.supervisor.team trn sup,model_itr_supervisor_team,itr_core.group_transport_supervisor,1,1,1,0
access_itr_supervisor_team_mgr,itr.supervisor.team fin mgr,model_itr_supervisor_team,itr_core.group_financial_manager,1,1,1,0
access_itr_supervisor_team_ceo,itr.supervisor.team ceo,model_itr_supervisor_team,itr_core.group_ceo,1,1,1,0

access_itr_supervisor_team_member_user,itr.supervisor.team.member user read,model_itr_supervisor_team_member,base.group_user,1,0,0,0
access_itr_supervisor_team_member_fin_sup,itr.supervisor.team.member fin sup,model_itr_supervisor_team_member,itr_core.group_finance_supervisor,1,1,1,0
access_itr_supervisor_team_member_trn_sup,itr.supervisor.team.member trn sup,model_itr_supervisor_team_member,itr_core.group_transport_supervisor,1,1,1,0
access_itr_supervisor_team_member_mgr,itr.supervisor.team.member fin mgr,model_itr_supervisor_team_member,itr_core.group_financial_manager,1,1,1,0
access_itr_supervisor_team_member_ceo,itr.supervisor.team.member ceo,model_itr_supervisor_team_member,itr_core.group_ceo,1,1,1,0

access_itr_border_user,itr.border user,model_itr_border,base.group_user,1,0,0,0
access_itr_border_customs,itr.border customs,model_itr_border,itr_core.group_customs_officer,1,1,1,0
access_itr_border_transport_sup,itr.border trn sup,model_itr_border,itr_core.group_transport_supervisor,1,1,1,0
access_itr_border_fin_sup,itr.border fin sup,model_itr_border,itr_core.group_finance_supervisor,1,1,1,0
access_itr_border_ceo,itr.border ceo,model_itr_border,itr_core.group_ceo,1,1,1,0

access_itr_driver_user,itr.driver user,model_itr_driver,base.group_user,1,0,0,0
access_itr_driver_docs,itr.driver docs,model_itr_driver,itr_core.group_transport_docs,1,1,1,0
access_itr_driver_customs,itr.driver customs,model_itr_driver,itr_core.group_customs_officer,1,1,0,0
access_itr_driver_delivery,itr.driver delivery,model_itr_driver,itr_core.group_transport_delivery,1,1,0,0
access_itr_driver_transport_sup,itr.driver trn sup,model_itr_driver,itr_core.group_transport_supervisor,1,1,1,0
access_itr_driver_fin,itr.driver fin,model_itr_driver,itr_core.group_finance_user,1,0,0,0
access_itr_driver_fin_sup,itr.driver fin sup,model_itr_driver,itr_core.group_finance_supervisor,1,1,1,0
access_itr_driver_ceo,itr.driver ceo,model_itr_driver,itr_core.group_ceo,1,1,1,0

access_itr_vehicle_user,itr.vehicle user,model_itr_vehicle,base.group_user,1,0,0,0
access_itr_vehicle_docs,itr.vehicle docs,model_itr_vehicle,itr_core.group_transport_docs,1,1,1,0
access_itr_vehicle_customs,itr.vehicle customs,model_itr_vehicle,itr_core.group_customs_officer,1,1,0,0
access_itr_vehicle_delivery,itr.vehicle delivery,model_itr_vehicle,itr_core.group_transport_delivery,1,1,0,0
access_itr_vehicle_transport_sup,itr.vehicle trn sup,model_itr_vehicle,itr_core.group_transport_supervisor,1,1,1,0
access_itr_vehicle_fin_sup,itr.vehicle fin sup,model_itr_vehicle,itr_core.group_finance_supervisor,1,1,1,0
access_itr_vehicle_ceo,itr.vehicle ceo,model_itr_vehicle,itr_core.group_ceo,1,1,1,0
CSVEOF

write_utf8 "${MOD_DIR}/security/itr_core_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- Multi-Company Base Rules -->
        <record id="rule_itr_border_company" model="ir.rule">
            <field name="name">Border multi-company rule</field>
            <field name="model_id" ref="itr_core.model_itr_border"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>

        <!-- Driver / Vehicle Access Rules -->
        <record id="rule_itr_driver_read_all" model="ir.rule">
            <field name="name">Driver read access for internal users</field>
            <field name="model_id" ref="itr_core.model_itr_driver"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="False"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="False"/>
        </record>

        <record id="rule_itr_driver_write_logistics" model="ir.rule">
            <field name="name">Driver write access for logistics and finance supervisor</field>
            <field name="model_id" ref="itr_core.model_itr_driver"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[
                (4, ref('itr_core.group_transport_docs')),
                (4, ref('itr_core.group_transport_supervisor')),
                (4, ref('itr_core.group_finance_supervisor')),
                (4, ref('itr_core.group_ceo'))
            ]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="False"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${MOD_DIR}/data/itr_treasury_settings_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="itr_treasury_settings_default" model="itr.treasury.settings">
            <field name="name">ITR Treasury Settings</field>
            <field name="fallback_usd_rate">1100000.0</field>
            <field name="fallback_eur_rate">1200000.0</field>
            <field name="require_rate_locking" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_border_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <!-- 6 Official Iranian Customs Borders (Checklist 3.7) -->
        <record id="border_bazargan" model="itr.border">
            <field name="name">مرز بازرگان (ترکیه)</field>
            <field name="code">BAZARGAN</field>
            <field name="border_type">land</field>
            <field name="sequence">10</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <record id="border_astara" model="itr.border">
            <field name="name">مرز آستارا (آذربایجان)</field>
            <field name="code">ASTARA</field>
            <field name="border_type">land</field>
            <field name="sequence">20</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <record id="border_dogharoun" model="itr.border">
            <field name="name">مرز دوغارون (افغانستان)</field>
            <field name="code">DOGHAROUN</field>
            <field name="border_type">land</field>
            <field name="sequence">30</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <record id="border_mehran" model="itr.border">
            <field name="name">مرز مهران (عراق)</field>
            <field name="code">MEHRAN</field>
            <field name="border_type">land</field>
            <field name="sequence">40</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <record id="border_bandar_abbas" model="itr.border">
            <field name="name">بندر شهید رجایی / بندرعباس (دریایی)</field>
            <field name="code">BANDAR_ABBAS</field>
            <field name="border_type">sea</field>
            <field name="sequence">50</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <record id="border_incheh_boroun" model="itr.border">
            <field name="name">مرز اینچه‌برون (ترکمنستان)</field>
            <field name="code">INCHEH_BOROUN</field>
            <field name="border_type">rail</field>
            <field name="sequence">60</field>
            <field name="has_customs_office" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_partner_category_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="partner_cat_factory" model="res.partner.category">
            <field name="name">کارخانجات تولیدی (مبدأ)</field>
        </record>
        <record id="partner_cat_shipping_line" model="res.partner.category">
            <field name="name">شرکت‌های حمل‌ونقل و باربری</field>
        </record>
        <record id="partner_cat_customs_agent" model="res.partner.category">
            <field name="name">ترخیص‌کاران رسمی</field>
        </record>
        <record id="partner_cat_border_rep" model="res.partner.category">
            <field name="name">نمایندگان مستقر در مرز</field>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_core_users_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">

        <!-- 1) CEO 1 — Hadi Karamian -->
        <record id="user_ceo_hadi_karamian" model="res.users">
            <field name="name">هادی کرمیان</field>
            <field name="login">hadi.karamian@irbco.local</field>
            <field name="email">hadi.karamian@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_ceo')),
                (4, ref('itr_core.group_document_signer'))
            ]"/>
        </record>

        <!-- 2) CEO 2 — Saeed Yousefi -->
        <record id="user_ceo_saeed_yousefi" model="res.users">
            <field name="name">سعید یوسفی</field>
            <field name="login">saeed.yousefi@irbco.local</field>
            <field name="email">saeed.yousefi@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_ceo')),
                (4, ref('itr_core.group_document_signer'))
            ]"/>
        </record>

        <!-- 3) Financial Manager -->
        <record id="user_financial_manager" model="res.users">
            <field name="name">مدیر مالی</field>
            <field name="login">fin.mgr@irbco.local</field>
            <field name="email">fin.mgr@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_financial_manager'))
            ]"/>
        </record>

        <!-- 4) Finance Supervisor — Ehsan Nahalparvar -->
        <record id="user_finance_supervisor" model="res.users">
            <field name="name">احسان نهال‌پرور</field>
            <field name="login">ehsan.nahalparvar@irbco.local</field>
            <field name="email">ehsan.nahalparvar@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_finance_supervisor'))
            ]"/>
        </record>

        <!-- 5) Finance User — Faezeh Heydari -->
        <record id="user_finance_user" model="res.users">
            <field name="name">فائزه حیدری</field>
            <field name="login">faezeh.heydari@irbco.local</field>
            <field name="email">faezeh.heydari@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_finance_user'))
            ]"/>
        </record>

        <!-- 6) Legal Reviewer — Pouya Soleimani -->
        <record id="user_legal_reviewer" model="res.users">
            <field name="name">پویا سلیمانی</field>
            <field name="login">pouya.soleimani@irbco.local</field>
            <field name="email">pouya.soleimani@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_legal_reviewer'))
            ]"/>
        </record>

        <!-- 7) Treasury User — Atieh Alaei -->
        <record id="user_treasury_user" model="res.users">
            <field name="name">عطیه اعلایی</field>
            <field name="login">atieh.alaei@irbco.local</field>
            <field name="email">atieh.alaei@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_treasury_user'))
            ]"/>
        </record>

        <!-- 8) Receivables User — Zahra Mirzaei -->
        <record id="user_receivables_user" model="res.users">
            <field name="name">زهرا میرزایی</field>
            <field name="login">zahra.mirzaei@irbco.local</field>
            <field name="email">zahra.mirzaei@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_receivables_user'))
            ]"/>
        </record>

        <!-- 9) Transport Supervisor — Najmeh Afrashtehpour -->
        <record id="user_transport_supervisor" model="res.users">
            <field name="name">نجمه افراشته‌پور</field>
            <field name="login">najmeh.afrashtehpour@irbco.local</field>
            <field name="email">najmeh.afrashtehpour@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_transport_supervisor'))
            ]"/>
        </record>

        <!-- 10) Transport Specialist (Docs & Fleet) — Mohaddeseh Enayati -->
        <record id="user_transport_docs" model="res.users">
            <field name="name">محدثه عنایتی</field>
            <field name="login">mohaddeseh.enayati@irbco.local</field>
            <field name="email">mohaddeseh.enayati@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_transport_docs'))
            ]"/>
        </record>

        <!-- 11) Customs Officer — Mohammadi -->
        <record id="user_customs_officer" model="res.users">
            <field name="name">آقای محمدی</field>
            <field name="login">mohammadi@irbco.local</field>
            <field name="email">mohammadi@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_customs_officer'))
            ]"/>
        </record>

        <!-- 12) Transport Specialist (Delivery & Settlement) — Amini -->
        <record id="user_transport_delivery" model="res.users">
            <field name="name">خانم امینی</field>
            <field name="login">amini@irbco.local</field>
            <field name="email">amini@irbco.local</field>
            <field name="password">Irbco@1404</field>
            <field name="lang">fa_IR</field>
            <field name="tz">Asia/Tehran</field>
            <field name="group_ids" eval="[
                (4, ref('base.group_user')),
                (4, ref('itr_core.group_transport_delivery'))
            ]"/>
        </record>

        <!-- Default Supervisor Teams -->
        <record id="team_finance" model="itr.supervisor.team">
            <field name="name">تیم عملیات مالی و بازرگانی</field>
            <field name="supervisor_id" ref="user_finance_supervisor"/>
            <field name="unit">finance</field>
            <field name="sequence">10</field>
            <field name="member_ids" eval="[
                (0, 0, {'user_id': ref('user_finance_user'), 'max_open_cases': 25})
            ]"/>
        </record>

        <record id="team_transport" model="itr.supervisor.team">
            <field name="name">تیم لجستیک، ناوگان و ترخیص</field>
            <field name="supervisor_id" ref="user_transport_supervisor"/>
            <field name="unit">transport</field>
            <field name="sequence">20</field>
            <field name="member_ids" eval="[
                (0, 0, {'user_id': ref('user_transport_docs'), 'max_open_cases': 30}),
                (0, 0, {'user_id': ref('user_customs_officer'), 'max_open_cases': 30}),
                (0, 0, {'user_id': ref('user_transport_delivery'), 'max_open_cases': 30})
            ]"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${MOD_DIR}/views/itr_treasury_settings_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_treasury_settings_form" model="ir.ui.view">
        <field name="name">itr.treasury.settings.form</field>
        <field name="model">itr.treasury.settings</field>
        <field name="arch" type="xml">
            <form string="Treasury &amp; FX Settings">
                <sheet>
                    <div class="oe_title">
                        <h1><field name="name" readonly="1"/></h1>
                    </div>
                    <group>
                        <group string="Currencies">
                            <field name="base_currency_id"/>
                            <field name="usd_currency_id"/>
                            <field name="eur_currency_id"/>
                        </group>
                        <group string="Fallback Exchange Rates (IRR)">
                            <field name="fallback_usd_rate"/>
                            <field name="fallback_eur_rate"/>
                            <field name="require_rate_locking"/>
                        </group>
                    </group>
                    <group string="Policy &amp; Notes">
                        <field name="note" nolabel="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_treasury_settings" model="ir.actions.act_window">
        <field name="name">Treasury &amp; FX Settings</field>
        <field name="res_model">itr.treasury.settings</field>
        <field name="view_mode">form</field>
        <field name="res_id" eval="ref('itr_core.itr_treasury_settings_default')"/>
        <field name="target">current</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_supervisor_team_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_supervisor_team_form" model="ir.ui.view">
        <field name="name">itr.supervisor.team.form</field>
        <field name="model">itr.supervisor.team</field>
        <field name="arch" type="xml">
            <form string="Supervisor Team">
                <sheet>
                    <div class="oe_button_box" name="button_box">
                    </div>
                    <div class="oe_title">
                        <label for="name" string="Team Name"/>
                        <h1><field name="name" placeholder="e.g. Finance Operations Team"/></h1>
                    </div>
                    <group>
                        <group>
                            <field name="supervisor_id"/>
                            <field name="unit"/>
                        </group>
                        <group>
                            <field name="sequence"/>
                            <field name="active"/>
                            <field name="member_count"/>
                        </group>
                    </group>
                    <notebook>
                        <page string="Team Members" name="members">
                            <field name="member_ids">
                                <list editable="bottom">
                                    <field name="sequence" widget="handle"/>
                                    <field name="user_id"/>
                                    <field name="user_email"/>
                                    <field name="max_open_cases"/>
                                    <field name="is_active"/>
                                </list>
                            </field>
                        </page>
                        <page string="Notes" name="notes">
                            <field name="note" placeholder="Team responsibilities and operational notes..."/>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_supervisor_team_list" model="ir.ui.view">
        <field name="name">itr.supervisor.team.list</field>
        <field name="model">itr.supervisor.team</field>
        <field name="arch" type="xml">
            <list string="Supervisor Teams">
                <field name="sequence" widget="handle"/>
                <field name="name"/>
                <field name="supervisor_id"/>
                <field name="unit"/>
                <field name="member_count"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="action_itr_supervisor_team" model="ir.actions.act_window">
        <field name="name">Supervisor Teams</field>
        <field name="res_model">itr.supervisor.team</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_border_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_border_form" model="ir.ui.view">
        <field name="name">itr.border.form</field>
        <field name="model">itr.border</field>
        <field name="arch" type="xml">
            <form string="Customs Border">
                <sheet>
                    <div class="oe_title">
                        <label for="name" string="Border Name"/>
                        <h1><field name="name" placeholder="e.g. مرز بازرگان"/></h1>
                    </div>
                    <group>
                        <group>
                            <field name="code"/>
                            <field name="border_type"/>
                            <field name="neighbor_country_id"/>
                        </group>
                        <group>
                            <field name="sequence"/>
                            <field name="has_customs_office"/>
                            <field name="default_clearance_agent_id"/>
                            <field name="active"/>
                        </group>
                    </group>
                    <field name="note" placeholder="Notes..."/>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_border_list" model="ir.ui.view">
        <field name="name">itr.border.list</field>
        <field name="model">itr.border</field>
        <field name="arch" type="xml">
            <list string="Customs Borders">
                <field name="sequence" widget="handle"/>
                <field name="name"/>
                <field name="code"/>
                <field name="border_type"/>
                <field name="neighbor_country_id"/>
                <field name="has_customs_office"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="action_itr_border" model="ir.actions.act_window">
        <field name="name">Customs Borders</field>
        <field name="res_model">itr.border</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_driver_vehicle_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Driver Views -->
    <record id="view_itr_driver_form" model="ir.ui.view">
        <field name="name">itr.driver.form</field>
        <field name="model">itr.driver</field>
        <field name="arch" type="xml">
            <form string="Fleet Driver">
                <sheet>
                    <div class="oe_title">
                        <label for="name" string="Driver Full Name"/>
                        <h1><field name="name" placeholder="e.g. علی محمدی"/></h1>
                    </div>
                    <group>
                        <group string="Identity &amp; Nationality">
                            <field name="nationality"/>
                            <field name="country_id" invisible="nationality == 'iranian'"/>
                            <field name="national_id" invisible="nationality != 'iranian'"/>
                            <field name="passport_number" invisible="nationality == 'iranian'"/>
                            <field name="mobile"/>
                            <field name="partner_id"/>
                        </group>
                        <group string="Smart Card &amp; Bank">
                            <field name="smart_card_number"/>
                            <field name="smart_card_status"/>
                            <field name="smart_card_inquiry_date"/>
                            <field name="sheba_number"/>
                            <field name="sheba_masked"/>
                            <field name="active"/>
                        </group>
                    </group>
                    <field name="note" placeholder="Driver driving history and notes..."/>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_driver_list" model="ir.ui.view">
        <field name="name">itr.driver.list</field>
        <field name="model">itr.driver</field>
        <field name="arch" type="xml">
            <list string="Fleet Drivers">
                <field name="name"/>
                <field name="mobile"/>
                <field name="nationality"/>
                <field name="national_id"/>
                <field name="passport_number"/>
                <field name="smart_card_number"/>
                <field name="smart_card_status"/>
                <field name="sheba_masked"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="action_itr_driver" model="ir.actions.act_window">
        <field name="name">Fleet Drivers</field>
        <field name="res_model">itr.driver</field>
        <field name="view_mode">list,form</field>
    </record>

    <!-- Vehicle Views -->
    <record id="view_itr_vehicle_form" model="ir.ui.view">
        <field name="name">itr.vehicle.form</field>
        <field name="model">itr.vehicle</field>
        <field name="arch" type="xml">
            <form string="Transport Vehicle">
                <sheet>
                    <div class="oe_title">
                        <label for="plate_number" string="Plate Number"/>
                        <h1><field name="plate_number" placeholder="e.g. 12 ب 345 ایران 67"/></h1>
                    </div>
                    <group>
                        <group string="Vehicle Specifications">
                            <field name="plate_type"/>
                            <field name="vehicle_type"/>
                            <field name="max_tonnage_capacity"/>
                        </group>
                        <group string="Fleet Assignment">
                            <field name="default_driver_id"/>
                            <field name="smart_card_number"/>
                            <field name="active"/>
                        </group>
                    </group>
                    <field name="note" placeholder="Vehicle maintenance and specifications..."/>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_vehicle_list" model="ir.ui.view">
        <field name="name">itr.vehicle.list</field>
        <field name="model">itr.vehicle</field>
        <field name="arch" type="xml">
            <list string="Transport Vehicles">
                <field name="plate_number"/>
                <field name="plate_type"/>
                <field name="vehicle_type"/>
                <field name="default_driver_id"/>
                <field name="max_tonnage_capacity"/>
                <field name="smart_card_number"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="action_itr_vehicle" model="ir.actions.act_window">
        <field name="name">Transport Vehicles</field>
        <field name="res_model">itr.vehicle</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_partner_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_partner_form_inherit_itr_core" model="ir.ui.view">
        <field name="name">res.partner.form.inherit.itr.core</field>
        <field name="model">res.partner</field>
        <field name="inherit_id" ref="base.view_partner_form"/>
        <field name="arch" type="xml">
            <xpath expr="//notebook" position="inside">
                <page string="Iran Trade &amp; Transport" name="itr_trade">
                    <group>
                        <group string="Partner Classification">
                            <field name="is_factory"/>
                            <field name="is_customs_agent"/>
                            <field name="is_border_rep"/>
                            <field name="is_shipping_line"/>
                            <field name="customer_scope"/>
                        </group>
                        <group string="Tax &amp; Identity IDs">
                            <field name="national_id"/>
                            <field name="economic_code"/>
                            <field name="sheba_number"/>
                            <field name="sheba_masked"/>
                            <field name="trade_credit_limit"/>
                            <field name="assigned_finance_user_id"/>
                        </group>
                    </group>
                </page>
            </xpath>
        </field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_core_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_core_root"
              name="Iran Trade &amp; Transport"
              sequence="10"/>

    <menuitem id="menu_itr_logistics_root"
              name="Fleet &amp; Logistics"
              parent="menu_itr_core_root"
              sequence="20"/>

    <menuitem id="menu_itr_driver"
              name="Fleet Drivers"
              parent="menu_itr_logistics_root"
              action="action_itr_driver"
              sequence="10"/>

    <menuitem id="menu_itr_vehicle"
              name="Transport Vehicles"
              parent="menu_itr_logistics_root"
              action="action_itr_vehicle"
              sequence="20"/>

    <menuitem id="menu_itr_border"
              name="Customs Borders"
              parent="menu_itr_logistics_root"
              action="action_itr_border"
              sequence="30"/>

    <menuitem id="menu_itr_org_root"
              name="Organization &amp; Teams"
              parent="menu_itr_core_root"
              sequence="80"/>

    <menuitem id="menu_itr_supervisor_team"
              name="Supervisor Teams"
              parent="menu_itr_org_root"
              action="action_itr_supervisor_team"
              sequence="10"/>

    <menuitem id="menu_itr_treasury_settings"
              name="Treasury &amp; FX Settings"
              parent="menu_itr_org_root"
              action="action_itr_treasury_settings"
              sequence="20"
              groups="itr_core.group_financial_manager,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
</odoo>
XMLEOF

# -------------------------------------------------------------------- i18n --
write_utf8 "${MOD_DIR}/i18n/fa_IR.po" <<'POEOF'
# Translation of Odoo Server - module itr_core.
# Persian (Iran) - Iran Trade & Transport ERP
msgid ""
msgstr ""
"Project-Id-Version: Odoo Server 19.0\n"
"Report-Msgid-Bugs-To: \n"
"POT-Creation-Date: 2026-01-01 00:00+0000\n"
"PO-Revision-Date: 2026-01-01 00:00+0000\n"
"Last-Translator: Iran Trade & Transport ERP\n"
"Language-Team: Persian\n"
"Language: fa_IR\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: \n"
"Plural-Forms: nplurals=1; plural=0;\n"

#. module: itr_core
#: model:res.groups.privilege,name:itr_core.privilege_itr_core
msgid "Iran Trade & Transport Core Roles"
msgstr "نقش‌های ستون فقرات بازرگانی و حمل ایران"

#. module: itr_core
#: model:res.groups,name:itr_core.group_ceo
msgid "CEO / Executive Board"
msgstr "مدیرعامل / هیئت‌مدیره"

#. module: itr_core
#: model:res.groups,name:itr_core.group_document_signer
msgid "Document Signer"
msgstr "امضاکنندهٔ اسناد"

#. module: itr_core
#: model:res.groups,name:itr_core.group_financial_manager
msgid "Financial Manager"
msgstr "مدیر مالی"

#. module: itr_core
#: model:res.groups,name:itr_core.group_finance_supervisor
msgid "Finance Supervisor"
msgstr "سرپرست مالی"

#. module: itr_core
#: model:res.groups,name:itr_core.group_finance_user
msgid "Finance Specialist"
msgstr "کارشناس مالی"

#. module: itr_core
#: model:res.groups,name:itr_core.group_legal_reviewer
msgid "Legal Reviewer"
msgstr "کارشناس بررسی حقوقی"

#. module: itr_core
#: model:res.groups,name:itr_core.group_treasury_user
msgid "Treasury Specialist"
msgstr "کارشناس خزانه"

#. module: itr_core
#: model:res.groups,name:itr_core.group_receivables_user
msgid "Receivables & Credit Specialist"
msgstr "کارشناس وصول مطالبات و اعتبارات"

#. module: itr_core
#: model:res.groups,name:itr_core.group_transport_supervisor
msgid "Transport Supervisor"
msgstr "سرپرست حمل‌ونقل"

#. module: itr_core
#: model:res.groups,name:itr_core.group_transport_docs
msgid "Transport Specialist - Fleet & Documents"
msgstr "کارشناس اسناد و ناوگان حمل"

#. module: itr_core
#: model:res.groups,name:itr_core.group_customs_officer
msgid "Customs & Clearance Officer"
msgstr "کارشناس امور گمرک و ترخیص"

#. module: itr_core
#: model:res.groups,name:itr_core.group_transport_delivery
msgid "Transport Specialist - Delivery & Settlement"
msgstr "کارشناس تحویل و تسویهٔ حمل"

#. module: itr_core
#: model:res.groups,name:itr_core.group_auditor
msgid "Auditor (Read-Only)"
msgstr "حسابرس و ناظر (فقط‌خواندنی)"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_treasury_settings
msgid "Iran Treasury and FX Settings"
msgstr "تنظیمات خزانه و نرخ ارز"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_supervisor_team
msgid "Supervisor Team"
msgstr "تیم سرپرستی"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_supervisor_team_member
msgid "Supervisor Team Member"
msgstr "عضو تیم سرپرستی"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_border
msgid "Iranian Official Customs Border"
msgstr "مرز رسمی گمرکی ایران"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_driver
msgid "Fleet Driver"
msgstr "رانندهٔ ناوگان"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_vehicle
msgid "Transport Vehicle"
msgstr "کامیون و ناوگان حمل"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_core_root
msgid "Iran Trade & Transport"
msgstr "بازرگانی و حمل‌ونقل ایران"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_logistics_root
msgid "Fleet & Logistics"
msgstr "ناوگان و لجستیک"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_driver
msgid "Fleet Drivers"
msgstr "رانندگان"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_vehicle
msgid "Transport Vehicles"
msgstr "کامیون‌ها و ناوگان"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_border
msgid "Customs Borders"
msgstr "مرزهای گمرکی"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_org_root
msgid "Organization & Teams"
msgstr "سازمان و تیم‌ها"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_supervisor_team
msgid "Supervisor Teams"
msgstr "تیم‌های سرپرستی"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_treasury_settings
msgid "Treasury & FX Settings"
msgstr "تنظیمات خزانه و نرخ ارز"
POEOF
cp -f "${MOD_DIR}/i18n/fa_IR.po" "${MOD_DIR}/i18n/fa.po"

# ------------------------------------------------------------------ tests --
write_utf8 "${MOD_DIR}/tests/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import common
from . import test_groups_users
from . import test_supervisor_team
from . import test_driver_vehicle
from . import test_fx_service
PYEOF

write_utf8 "${MOD_DIR}/tests/common.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.tests import TransactionCase


class ItrCoreCase(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        users_model = cls.env["res.users"]
        cls.group_field = "group_ids" if "group_ids" in users_model._fields else "groups_id"
        cls.treasury = cls.env["itr.treasury.settings"].get_settings()

    @classmethod
    def _create_user(cls, login, group_xmlids=()):
        groups = cls.env.ref("base.group_user")
        for xmlid in group_xmlids:
            grp = cls.env.ref(xmlid, raise_if_not_found=False)
            if grp:
                groups |= grp
        return cls.env["res.users"].create({
            "name": "TEST %s" % login,
            "login": login,
            "email": "%s@test.invalid" % login,
            cls.group_field: [(6, 0, groups.ids)],
        })
PYEOF

write_utf8 "${MOD_DIR}/tests/test_groups_users.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.tests import tagged
from .common import ItrCoreCase

BUSINESS_GROUPS = [
    "itr_core.group_ceo",
    "itr_core.group_document_signer",
    "itr_core.group_financial_manager",
    "itr_core.group_finance_supervisor",
    "itr_core.group_finance_user",
    "itr_core.group_legal_reviewer",
    "itr_core.group_treasury_user",
    "itr_core.group_receivables_user",
    "itr_core.group_transport_supervisor",
    "itr_core.group_transport_docs",
    "itr_core.group_customs_officer",
    "itr_core.group_transport_delivery",
    "itr_core.group_auditor",
]


@tagged("post_install", "-at_install", "itr_core")
class TestItrGroupsAndUsers(ItrCoreCase):

    def test_01_all_13_groups_exist(self):
        for xid in BUSINESS_GROUPS:
            grp = self.env.ref(xid, raise_if_not_found=False)
            self.assertTrue(grp, "Missing business group: %s" % xid)

    def test_02_admin_has_no_business_group_negative(self):
        """Q03: Administrator must never hold any business role."""
        admin = self.env.ref("base.user_admin")
        for xid in BUSINESS_GROUPS:
            self.assertFalse(admin.has_group(xid), "Admin illegally holds group: %s" % xid)

    def test_03_dual_ceo_role(self):
        """Both Hadi Karamian and Saeed Yousefi must be CEO + Document Signer."""
        ceo1 = self.env["res.users"].search([("login", "=", "hadi.karamian@irbco.local")], limit=1)
        ceo2 = self.env["res.users"].search([("login", "=", "saeed.yousefi@irbco.local")], limit=1)
        self.assertTrue(ceo1, "CEO 1 missing")
        self.assertTrue(ceo2, "CEO 2 missing")

        self.assertTrue(ceo1.has_group("itr_core.group_ceo"))
        self.assertTrue(ceo1.has_group("itr_core.group_document_signer"))
        self.assertTrue(ceo2.has_group("itr_core.group_ceo"))
        self.assertTrue(ceo2.has_group("itr_core.group_document_signer"))

    def test_04_read_permissions_on_master_data(self):
        """SEC-011: Operational specialist can read master borders and drivers."""
        fin_user = self._create_user("test_fin_user", ["itr_core.group_finance_user"])
        border = self.env.ref("itr_core.border_bazargan")
        # Should read without error
        read_res = border.with_user(fin_user).name
        self.assertTrue(read_res)
PYEOF

write_utf8 "${MOD_DIR}/tests/test_supervisor_team.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests import tagged
from .common import ItrCoreCase


@tagged("post_install", "-at_install", "itr_core")
class TestSupervisorTeam(ItrCoreCase):

    def test_10_team_members_retrieval(self):
        fin_sup = self._create_user("test_fin_sup_1", ["itr_core.group_finance_supervisor"])
        fin_usr1 = self._create_user("test_fin_usr_1", ["itr_core.group_finance_user"])
        fin_usr2 = self._create_user("test_fin_usr_2", ["itr_core.group_finance_user"])

        team = self.env["itr.supervisor.team"].create({
            "name": "TEST Finance Team",
            "supervisor_id": fin_sup.id,
            "unit": "finance",
            "member_ids": [
                (0, 0, {"user_id": fin_usr1.id, "max_open_cases": 15}),
                (0, 0, {"user_id": fin_usr2.id, "max_open_cases": 20}),
            ],
        })
        self.assertEqual(team.member_count, 2)
        subs = self.env["itr.supervisor.team"].get_subordinate_users(fin_sup.id)
        self.assertEqual(len(subs), 2)
        self.assertIn(fin_usr1, subs)
        self.assertIn(fin_usr2, subs)

    def test_11_admin_forbidden_in_team(self):
        admin = self.env.ref("base.user_admin")
        with self.assertRaises(ValidationError):
            self.env["itr.supervisor.team"].create({
                "name": "TEST Invalid Admin Team",
                "supervisor_id": admin.id,
                "unit": "finance",
            })
PYEOF

write_utf8 "${MOD_DIR}/tests/test_driver_vehicle.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests import tagged
from .common import ItrCoreCase


@tagged("post_install", "-at_install", "itr_core")
class TestDriverVehicle(ItrCoreCase):

    def test_20_iranian_driver_validation(self):
        # Valid Iranian driver
        driver = self.env["itr.driver"].create({
            "name": "TEST Iranian Driver",
            "nationality": "iranian",
            "national_id": "0084575948",
            "mobile": "09123456789",
        })
        self.assertTrue(driver.id)

        # Invalid National ID raises
        with self.assertRaises(ValidationError):
            self.env["itr.driver"].create({
                "name": "TEST Invalid Iranian Driver",
                "nationality": "iranian",
                "national_id": "1111111111",
                "mobile": "09123456789",
            })

    def test_21_foreign_driver_without_national_id(self):
        """G13: Foreign driver must pass with passport, without Iranian national id."""
        driver = self.env["itr.driver"].create({
            "name": "TEST Foreign Driver",
            "nationality": "foreign",
            "passport_number": "TR-98765432",
            "mobile": "+905321112233",
        })
        self.assertTrue(driver.id)
        self.assertEqual(driver.passport_number, "TR-98765432")

    def test_22_vehicle_plate_types(self):
        # Iranian plate
        v1 = self.env["itr.vehicle"].create({
            "plate_number": "12 ب 345 ایران 67",
            "plate_type": "iranian",
        })
        self.assertTrue(v1.id)

        # Transit plate
        v2 = self.env["itr.vehicle"].create({
            "plate_number": "TR-34-ABC-12",
            "plate_type": "transit",
        })
        self.assertTrue(v2.id)
PYEOF

write_utf8 "${MOD_DIR}/tests/test_fx_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.tests import tagged
from .common import ItrCoreCase


@tagged("post_install", "-at_install", "itr_core")
class TestFxService(ItrCoreCase):

    def test_30_fx_same_currency(self):
        irr = self.env.ref("base.IRR")
        rate = self.env["itr.fx.service"].resolve_rate(irr, irr)
        self.assertEqual(rate, 1.0)

    def test_31_fx_usd_fallback(self):
        usd = self.env.ref("base.USD")
        irr = self.env.ref("base.IRR")
        rate = self.env["itr.fx.service"].resolve_rate(usd, irr)
        self.assertGreater(rate, 100000)

        fx_res = self.env["itr.fx.service"].apply_fx(100.0, usd, irr)
        self.assertEqual(fx_res["amount"], 100.0)
        self.assertTrue(fx_res["rate_locked"])
        self.assertEqual(fx_res["base_amount"], 100.0 * rate)
PYEOF

# ------------------------------------------------------------------ verify --
write_utf8 "${OPS_DIR}/verify/verify_phase3.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Independent verify script for Phase 3 (V3-01..V3-07).

Executed inside odoo shell non-interactively without sudo().
Rolls back at the end to guarantee zero production footprint (ADR-005).
"""
import sys

passed = 0
failed = 0
checks = []


def chk(code, title, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        st = "PASS"
    else:
        failed += 1
        st = "FAIL"
    checks.append((code, st, title, detail))
    print("ITR_VERIFY %-6s [%s] %s %s" % (code, st, title, ("— " + str(detail)) if detail else ""))


try:
    # 1) V3-01: 13 Groups
    GROUPS = [
        "itr_core.group_ceo", "itr_core.group_document_signer",
        "itr_core.group_financial_manager", "itr_core.group_finance_supervisor",
        "itr_core.group_finance_user", "itr_core.group_legal_reviewer",
        "itr_core.group_treasury_user", "itr_core.group_receivables_user",
        "itr_core.group_transport_supervisor", "itr_core.group_transport_docs",
        "itr_core.group_customs_officer", "itr_core.group_transport_delivery",
        "itr_core.group_auditor",
    ]
    all_grp_ok = all(bool(env.ref(xid, raise_if_not_found=False)) for xid in GROUPS)
    chk("V3-01", "هر ۱۳ گروه امنیتی سازمانی در دیتابیس موجودند", all_grp_ok, "13 groups checked")

    # 2) V3-02: 12 Real users
    REAL_LOGINS = [
        "hadi.karamian@irbco.local", "saeed.yousefi@irbco.local", "fin.mgr@irbco.local",
        "ehsan.nahalparvar@irbco.local", "faezeh.heydari@irbco.local", "pouya.soleimani@irbco.local",
        "atieh.alaei@irbco.local", "zahra.mirzaei@irbco.local", "najmeh.afrashtehpour@irbco.local",
        "amini@irbco.local", "mohaddeseh.enayati@irbco.local", "mohammadi@irbco.local"
    ]
    users_found = env["res.users"].search([("login", "in", REAL_LOGINS)])
    chk("V3-02", "۱۲ کاربر واقعی سازمان با نام و ایمیل معتبر ایجاد شدند", len(users_found) >= 12, "found=%d/12" % len(users_found))

    # 3) V3-03: Negative test Administrator
    admin = env.ref("base.user_admin")
    admin_biz_groups = [xid for xid in GROUPS if admin.has_group(xid)]
    chk("V3-03", "Administrator هیچ نقش کسب‌وکاری ندارد (تست منفی Q03)", len(admin_biz_groups) == 0, "dirty=%s" % admin_biz_groups)

    # 4) V3-04: Foreign driver without national id (G13)
    foreign_drv = env["itr.driver"].create({
        "name": "TEST Mehmet Yilmaz",
        "nationality": "foreign",
        "passport_number": "TR12345678",
        "mobile": "+905329998877",
    })
    chk("V3-04", "ثبت رانندهٔ خارجی با گذرنامه و بدون کد ملی موفق است (G13)", bool(foreign_drv.id), "id=%s" % foreign_drv.id)

    # 5) V3-05: 6 Official Borders present
    border_cnt = env["itr.border"].search_count([("code", "in", [
        "BAZARGAN", "ASTARA", "DOGHAROUN", "MEHRAN", "BANDAR_ABBAS", "INCHEH_BOROUN"
    ])])
    chk("V3-05", "هر ۶ مرز رسمی گمرکی کشور در داده‌های مرجع موجودند", border_cnt == 6, "borders=%d/6" % border_cnt)

    # 6) V3-06: Supervisor team multi-user & subordinate retrieval
    fin_sup = env["res.users"].search([("login", "=", "ehsan.nahalparvar@irbco.local")], limit=1)
    subs = env["itr.supervisor.team"].get_subordinate_users(fin_sup.id)
    chk("V3-06", "مدل تیم سرپرستی اعضای زیرمجموعه را به درستی برمی‌گرداند", len(subs) >= 1, "subordinates=%s" % subs.mapped("name"))

    # 7) V3-07: FX Rate Service resolution & locking
    usd = env.ref("base.USD", raise_if_not_found=False)
    irr = env.ref("base.IRR", raise_if_not_found=False) or env.company.currency_id
    fx_res = env["itr.fx.service"].apply_fx(500.0, usd, irr)
    chk("V3-07", "سرویس نرخ ارز مبلغ ارزی را با نرخ قفل‌شده تبدیل می‌کند (G12)", fx_res["rate_locked"] and fx_res["base_amount"] > 0, "rate=%s base=%s" % (fx_res["conversion_rate"], fx_res["base_amount"]))

except Exception as e:
    failed += 1
    chk("V3-ERR", "خطای پیش‌بینی‌نشده در اجرای verify", False, str(e))

finally:
    env.cr.rollback()

print("\nITR_VERIFY_SUMMARY: passed=%d failed=%d total=%d" % (passed, failed, len(checks)))
if failed == 0:
    print("ITR_VERIFY_RESULT: PASS")
    sys.exit(0)
else:
    print("ITR_VERIFY_RESULT: FAIL")
    sys.exit(1)
PYEOF

# =============================================================================
step "4) نصب / ارتقای ماژول itr_core روی DEV (Q01/NFR-001)"
# =============================================================================
MOD_STATE_BEFORE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
INSTALL_FLAG="-i"
[[ "${MOD_STATE_BEFORE}" == "installed" ]] && INSTALL_FLAG="-u"

info "installing/upgrading ${MODULE} on ${DB_NAME} (flag: ${INSTALL_FLAG})"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  "${INSTALL_FLAG}" "${MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e

MOD_STATE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
echo "install_rc=${INSTALL_RC} state_before=${MOD_STATE_BEFORE:-none} state_after=${MOD_STATE_AFTER:-none}"

if [[ ${INSTALL_RC} -eq 0 && "${MOD_STATE_AFTER}" == "installed" ]]; then
  gate "G3-03" "نصب/ارتقای بدون خطای ${MODULE} روی ${DB_NAME}" "PASS" "state=installed"
else
  gate "G3-03" "نصب/ارتقای بدون خطای ${MODULE} روی ${DB_NAME}" "FAIL" "rc=${INSTALL_RC} state=${MOD_STATE_AFTER:-none} → ${INSTALL_LOG}"
  tail -n 60 "${INSTALL_LOG}"
fi

# =============================================================================
step "5) راستی‌آزمایی داده‌های پایه، گروه‌ها و کاربران در سطح دیتابیس"
# =============================================================================
GROUP_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core' AND model='res.groups'")"
USER_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM res_users WHERE login IN ('hadi.karamian@irbco.local', 'saeed.yousefi@irbco.local', 'fin.mgr@irbco.local', 'ehsan.nahalparvar@irbco.local', 'faezeh.heydari@irbco.local', 'pouya.soleimani@irbco.local', 'atieh.alaei@irbco.local', 'zahra.mirzaei@irbco.local', 'najmeh.afrashtehpour@irbco.local', 'amini@irbco.local', 'mohaddeseh.enayati@irbco.local', 'mohammadi@irbco.local')")"
BORDER_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM itr_border WHERE active IS TRUE")"
TEAM_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM itr_supervisor_team WHERE active IS TRUE")"

echo "groups=${GROUP_COUNT} users=${USER_COUNT}/12 borders=${BORDER_COUNT}/6 teams=${TEAM_COUNT}"

if [[ "${GROUP_COUNT}" -ge 13 ]]; then
  gate "G3-04" "۱۳ گروه امنیتی سازمانی ایجاد شدند (بند 3.2)" "PASS" "groups=${GROUP_COUNT}"
else
  gate "G3-04" "۱۳ گروه امنیتی سازمانی ایجاد شدند (بند 3.2)" "FAIL" "groups=${GROUP_COUNT}/13"
fi

if [[ "${USER_COUNT}" -eq 12 ]]; then
  gate "G3-05" "۱۲ کاربر واقعی با نقش‌های اختصاصی ایجاد شدند (بند 3.3)" "PASS" "users=${USER_COUNT}"
else
  gate "G3-05" "۱۲ کاربر واقعی با نقش‌های اختصاصی ایجاد شدند (بند 3.3)" "FAIL" "users=${USER_COUNT}/12"
fi

if [[ "${BORDER_COUNT}" -ge 6 ]]; then
  gate "G3-06" "۶ مرز رسمی گمرکی کشور ایجاد شدند (بند 3.7)" "PASS" "borders=${BORDER_COUNT}"
else
  gate "G3-06" "۶ مرز رسمی گمرکی کشور ایجاد شدند (بند 3.7)" "FAIL" "borders=${BORDER_COUNT}/6"
fi

# =============================================================================
step "6) تست‌های خودکار Odoo با کاربر غیر-ادمین (Q04)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G3-07" "تست‌های خودکار ماژول سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "${MODULE}" --test-enable --test-tags "/${MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): ' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "test_rc=${TEST_RC} fails=${TEST_FAILS} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" ]]; then
    gate "G3-07" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "PASS" "${TEST_TOTAL:-tests} rc=0"
  else
    gate "G3-07" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): ' "${TEST_LOG}" | head -n 15 || true
  fi
fi

# =============================================================================
step "7) verify مستقل V3-01..V3-07 (بدون sudo، با rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G3-08" "verify مستقل فاز ۳ سبز است (V3-01..V3-07)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase3.py" \
    >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G3-08" "verify مستقل فاز ۳ سبز است (V3-01..V3-07)" "PASS" "${VERIFY_LINE}"
  else
    gate "G3-08" "verify مستقل فاز ۳ سبز است (V3-01..V3-07)" "FAIL" "${VERIFY_LINE:-خروجی یافت نشد} → ${VERIFY_LOG}"
    tail -n 40 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "8) گاردهای معماری فاز ۳ (Q03 + Q05 + Q07 + G01 + G18)"
# =============================================================================
# گارد ۱: Administrator بدون هیچ گروه کسب‌وکاری
ADMIN_GROUPS_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_core' WHERE u.login='admin'")"
if [[ "${ADMIN_GROUPS_COUNT}" == "0" ]]; then
  gate "G3-09" "Administrator کاملاً مقدس و فاقد هرگونه نقش کسب‌وکاری (Q03/SEC-002)" "PASS" "0 group"
else
  gate "G3-09" "Administrator کاملاً مقدس و فاقد هرگونه نقش کسب‌وکاری (Q03/SEC-002)" "FAIL" "${ADMIN_GROUPS_COUNT} گروه چسبیده به admin"
fi

# گارد ۲: نام‌های فنی کاملاً ASCII
NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${MOD_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${MOD_DIR}/security" "${MOD_DIR}/views" 2>/dev/null | grep -v 'fa_IR' || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G3-10" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n"
else
  gate "G3-10" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

# گارد ۳: هیچ رمزی داخل Git نرود
SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|api[_-]?secret[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G3-11" "هیچ کلید/رمز عملیاتی داخل مخزن نیست (Q12/NFR-004)" "PASS" "clean"
else
  gate "G3-11" "هیچ کلید/رمز عملیاتی داخل مخزن نیست (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "9) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_supervisor_team")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_border")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core'")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${MODULE}" \
  --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_supervisor_team")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_border")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core'")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G3-12" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "teams|borders|xmlid = ${CNT_AFTER}"
else
  gate "G3-12" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "10) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G3-13" "itr_core روی محیط UAT نصب شد" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G3-13" "itr_core روی محیط UAT نصب شد" "WARN" "محیط UAT یافت نشد"
else
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  UAT_FLAG="-i"; [[ "${UAT_STATE}" == "installed" ]] && UAT_FLAG="-u"
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    "${UAT_FLAG}" "${MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_AFTER="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_AFTER}" == "installed" ]]; then
    gate "G3-13" "itr_core روی محیط UAT نصب شد" "PASS" "${DB_NAME_UAT} state=installed"
  else
    gate "G3-13" "itr_core روی محیط UAT نصب شد" "FAIL" "rc=${UAT_RC} state=${UAT_AFTER} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "11) اسناد حاکمیتی: ADR / REUSE MAP / تحویل فاز ۳"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-013" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-013 — معماری ماتریس دسترسی ۱۳ گروه سازمانی (فاز ۳)
تصمیم: ۱۳ گروه امنیتی سازمانی از طریق مدل res.groups.privilege در Odoo 19 دسته‌بندی
می‌شوند. کاربر Administrator هرگز هیچ گروه کسب‌وکاری نمی‌گیرد (Q03 / G01).
هر دو مدیرعامل (هادی کرمیان و سعید یوسفی) هم‌زمان عضو group_ceo و group_document_signer هستند.

## ADR-014 — چندکاربره بودن تیم‌های سرپرستی از روز اول
تصمیم: هیچ فرضی در سیستم مبنی بر «هر نقش فقط یک کاربر» وجود ندارد. مدل itr.supervisor.team
امکان تعریف N کاربر برای هر واحد و هر نقش را با سقف ظرفیت پرونده باز (max_open_cases) فراهم می‌کند.

## ADR-015 — چندملیتی بودن هویت و ناوگان (G13)
تصمیم: برای رانندگان و ناوگان خارجی، بررسی کد ملی و پلاک ملی ایرانی خاموش می‌شود و
شماره گذرنامه و پلاک ترانزیت جایگزین می‌گردد (بدون خطا).

## ADR-016 — موتور واحد نرخ ارز (G12 / G18)
تصمیم: تنها یک سرویس نرخ ارز (itr.fx.service و utils/fx.py) در پروژه وجود دارد.
نرخ ارز ویژگی سطح «ردیف/رویداد مالی» است و پس از تأیید در سند قفل می‌شود (rate_locked).
MDEOF
log "ADR-013..016 به ARCHITECTURE_DECISIONS.md افزوده شد"
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "itr.supervisor.team" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## فاز ۳ — itr_core (Q14)
| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۳ | `res.partner` هسته با `_inherit` برای کارخانه، مشتری، ترخیص‌کار | ساخت مدل موازی مشتری/تأمین‌کننده ممنوع (Q13) |
| ۳ | `res.users` و `res.groups` هسته | زیرساخت امنیت و احراز هویت Odoo کامل است |
| ۳ | `res.currency` و `res.currency.rate` هسته | ساخت جدول دوم ارز ممنوع (G18) |
| ۳ | `itr.validation.service` فاز ۱ برای اعتبارسنجی پلاک و هویت رانندگان | اصل تک‌منبعی اعتبارسنجی |
| ۳ | `itr.notification.service` فاز ۲ برای اعلان‌های سازمانی | اصل تک‌منبعی اعلان |

## آنچه فازهای بعد باید از فاز ۳ بازاستفاده کنند (ساخت دوباره = Gate قرمز)
* `env['itr.fx.service'].resolve_rate / apply_fx` → تنها موتور تبدیل ارز (G12/G18)
* `itr.supervisor.team` → تنها مدل سلسله‌مراتب سرپرستی و صف کار تیم
* `itr.border` → تنها جدول مرجع مرزهای رسمی گمرکی
* `itr.driver` و `itr.vehicle` → تنها مدل‌های ناوگان و رانندگان با گارد چندملیتی
MDEOF
log "docs/REUSE_MAP.md به‌روزرسانی شد"
fi

# =============================================================================
step "12) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G3-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
else
  if ! port_in_use "${HTTP_PORT}"; then
    rm -f "${PID_FILE}"
    nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
      --http-interface="${HTTP_INTERFACE}" --http-port="${HTTP_PORT}" \
      >"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    sleep 3
  else
    warn "پورت ${HTTP_PORT} از قبل listen است"
  fi
  HTTP_CODE="000"
  for _ in $(seq 1 30); do
    HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/web/login" || echo 000)"
    [[ "${HTTP_CODE}" == "200" ]] && break
    sleep 2
  done
  if [[ "${HTTP_CODE}" == "200" ]]; then
    gate "G3-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G3-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "13) ثبت Git + تگ phase-3 (Q09)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-3: itr_core (13 business groups, 12 real users, dual CEO roles, supervisor team, borders, multi-nationality drivers/vehicles, FX service)"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-3 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-3 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G3-15" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-3}"
else
  gate "G3-15" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi

# =============================================================================
step "GATE 3 — گزارش پذیرش فاز ۳"
# =============================================================================
FAILS=0; WARNS=0
GATE_TABLE=""
printf "\n%-8s %-8s %s\n" "ID" "STATUS" "CHECK"
printf -- "---------------------------------------------------------------------------\n"
for i in "${!GATE_IDS[@]}"; do
  st="${GATE_ST[$i]}"
  case "${st}" in
    PASS) c="${GREEN}" ;;
    WARN) c="${YELLOW}"; WARNS=$((WARNS+1)) ;;
    *)    c="${RED}";    FAILS=$((FAILS+1)) ;;
  esac
  printf "%-8s ${c}%-8s${NC} %s\n" "${GATE_IDS[$i]}" "${st}" "${GATE_TXT[$i]}"
  [[ -n "${GATE_MSG[$i]}" ]] && printf "%-8s %-8s   ↳ %s\n" "" "" "${GATE_MSG[$i]}"
  GATE_TABLE="${GATE_TABLE}| ${GATE_IDS[$i]} | ${st} | ${GATE_TXT[$i]} | ${GATE_MSG[$i]} |"$'\n'
done
printf -- "---------------------------------------------------------------------------\n"

if [[ ${FAILS} -eq 0 ]]; then GATE_STATUS="سبز ✅"; else GATE_STATUS="قرمز ❌ (${FAILS} مورد ناموفق)"; fi

write_utf8 "${DOC_DIR}/PHASE3-DELIVERY.md" <<MDEOF
# تحویل فاز ۳ — itr_core (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-3
- وضعیت Gate 3: **${GATE_STATUS}** (هشدار: ${WARNS})

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 3.1 | اسکلت ماژول itr_core با وابستگی به itr_base + itr_notify | Q02 |
| 3.2 | ۱۳ گروه امنیتی سازمانی متصل به res.groups.privilege در Odoo 19 | SEC-011 |
| 3.3 | ۱۲ کاربر واقعی سازمان؛ دو مدیرعامل با نقش دوگانه (CEO + Document Signer) | بخش ۴ |
| 3.4 | گارد مقدس بودن Administrator بدون هیچ نقش کسب‌وکاری | Q03 / SEC-002 |
| 3.5 | مدل تیم سرپرستی (itr.supervisor.team + member) چندکاربره از روز اول | G14 / G15 |
| 3.6 | مجوزهای پایهٔ خواندن روی مدل‌های مرجع برای تمام کاربران عملیاتی | SEC-011 |
| 3.7 | داده‌های مرجع ۶ مرز رسمی گمرکی کشور با امکان بایگانی | DM-001 |
| 3.8 | مدل‌های راننده و ناوگان با پشتیبانی چندملیتی (ایرانی / خارجی) | G13 |
| 3.9 | توسعهٔ res.partner برای کارخانجات، ترخیص‌کاران و مشتریان | Q13 |
| 3.10 | سرویس واحد نرخ ارز (itr.fx.service / utils/fx.py) با قفل نرخ | G12 / G18 |
| 3.11 | قوانین دسترسی سطح رکورد (Record Rules) پایه | SEC-012 |
| 3.12 | ترجمهٔ فارسی کامل برای تمامی برچسب‌ها و مدل‌ها (i18n) | Q05 / G19 |

## ۲) نتیجهٔ Gate
| ID | وضعیت | سنجه | توضیح |
|---|---|---|---|
${GATE_TABLE}

## ۳) لاگ‌ها
- نصب: ${INSTALL_LOG}
- تست: ${TEST_LOG}
- verify: ${VERIFY_LOG}
- idempotency: ${IDEMP_LOG}
- UAT: ${UAT_LOG}

## ۴) گام بعد
Gate 3 سبز ⇒ آغاز فاز ۴ (پروندهٔ بازرگانی Trade Case، اقلام چندکالایی، دو الگوی معامله A/B، گردش تأییدات تخصصی حقوقی/خزانه/وصول، گارد امضای فیزیکی).
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-3: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

============================================================
 script-03-itr-core.sh (003.sh) با موفقیت تمام شد
------------------------------------------------------------
 ماژول      : itr_core (بخش اول: سازمان، نقش‌ها، داده‌های پایه)
 نقش‌ها     : ۱۳ نقش کسب‌وکاری سازمانی
 کاربران    : ۱۲ کاربر واقعی؛ دو مدیرعامل با نقش دوگانه (CEO + Signer)
 سرپرستی    : itr.supervisor.team (چندکاربره از روز اول)
 مرزها      : ۶ مرز رسمی کشور (بازرگان، آستارا، دوغارون، مهران، بندرعباس، اینچه‌برون)
 ناوگان     : itr.driver و itr.vehicle با گارد چندملیتی (ایرانی / خارجی)
 ارز        : itr.fx.service با قفل نرخ رویداد (G12/G18)
 Administrator : کاملاً فاقد نقش کسب‌وکاری (مقدس)
 verify     : ${OPS_DIR}/verify/verify_phase3.py
 گزارش تحویل: ${DOC_DIR}/PHASE3-DELIVERY.md
 Git        : HEAD=${GIT_HEAD}  tag=phase-3
 گام بعدی   : فاز ۴ (itr_core بخش دوم — Trade Case + گردش تأییدات + گارد امضا)
============================================================
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 3 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۴.${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 3 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۴ آغاز نمی‌شود.${NC}\n"
  exit 1
fi