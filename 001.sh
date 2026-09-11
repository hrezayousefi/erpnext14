
#!/usr/bin/env bash
# =============================================================================
# script-01-itr-base.sh — PHASE 1 (COMPLETE) — Iran Trade & Transport ERP
# Odoo 19.0 | File-First | Idempotent | Test-First | Gate-Enforced | No sudo-proof
#
# ماژول زیرساخت پایهٔ ایرانی: itr_base
# پوشش کامل چک‌لیست فاز ۱ نقشهٔ راه MASTER:
#   1.1 اسکلت رسمی ماژول (وابستگی فقط به base)
#   1.2 توابع خالص: ارقام فارسی/عربی↔لاتین، کد ملی، موبایل، شبا (Mod-97)،
#       نرمال‌سازی پلاک، ماسک شبا (IR93****0872)
#   1.3 تقویم جلالی (ADR-001): ذخیره میلادی/نمایش جلالی + تست رفت‌وبرگشت
#       روی بیش از ۵۰ تاریخ مرزی (نوروز، ۲۹/۳۰ اسفند، سال کبیسه)
#   1.4 مدل itr.common.settings (تک‌رکوردی) با ۴ کلید فعال/غیرفعال
#   1.5 مدل itr.validation.bypass.log (بدون امکان حذف، دلیل اجباری)
#   1.6 گروه‌های امنیتی group_itr_validation_override + group_itr_settings_manager
#   1.7 لایهٔ نازک Guarded (itr.validation.service) — سنجهٔ ایرانی فقط برای «ایرانی»
#   1.8 فایل ترجمهٔ فارسی (i18n/fa_IR.po + fa.po)
#   1.9 تست‌های خودکار با کاربر غیر-ادمین (≥ ۱۲ سناریوی مثبت/منفی + تاریخ + لاگ عبور)
#   verify مستقل V1-01..V1-08 (بدون sudo، با کاربر واقعی) + Gate 1 سبز/قرمز
#
# پیش‌نیاز: Gate 0 سبز (script-00-site-bootstrap.sh)
#
# استفاده:
#   chmod +x script-01-itr-base.sh
#   bash script-01-itr-base.sh
#
# سوییچ‌ها (پیش‌فرض همه فعال):
#   SKIP_TESTS=1        از اجرای تست‌های خودکار Odoo رد شو (Gate قرمز می‌شود)
#   SKIP_VERIFY=1       از اجرای verify مستقل رد شو (Gate قرمز می‌شود)
#   SKIP_UAT=1          نصب روی پایگاه‌دادهٔ UAT انجام نشود
#   START_DAEMON=0      سرویس Odoo دوباره اجرا نشود
#   SKIP_BACKUP=1       پشتیبان پیش از ارتقا گرفته نشود (توصیه نمی‌شود)
# =============================================================================
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8

# ───────────────────────────── CONFIG (هم‌راستا با فاز ۰) ────────────────────
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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase1-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase1-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase1-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase1-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase1-uat.log}"

MODULE="itr_base"
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

trap 'ec=$?; [[ $ec -ne 0 ]] && echo -e "\n${RED}[FATAL]${NC} exit=$ec — آخرین لاگ‌ها: ${INSTALL_LOG} / ${TEST_LOG} / ${VERIFY_LOG}"' EXIT

[[ "$(id -u)" -eq 0 ]] && err "با کاربر عادی اجرا کنید (نه root)."

write_utf8() {
  local target="$1" tmp
  tmp="$(mktemp)"; cat >"$tmp"
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
}

have()      { command -v "$1" >/dev/null 2>&1; }
db_exists() { psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${1}'" 2>/dev/null | grep -q 1; }
q()         { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }
port_in_use() { ss -lntp 2>/dev/null | grep -q ":${1} " && return 0 || return 1; }

# =============================================================================
step "0) preflight — Gate 0 باید سبز باشد"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد: ${CONF_FILE} (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G1-00" "نسخهٔ Odoo 19 تأیید شد (privilege_id/group_ids)" "PASS" "${ODOO_V}"
else
  gate "G1-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "نسخهٔ یافت‌شده: ${ODOO_V} — این ماژول برای Odoo 19 نوشته شده است"
  err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود (res.groups.privilege_id / res.users.group_ids)."
fi

ADDONS_IN_CONF="$(grep -E '^addons_path' "${CONF_FILE}" | head -n1 || true)"
echo "${ADDONS_IN_CONF}" | grep -q "${CUSTOM_ADDONS}" \
  || err "addons_path در ${CONF_FILE} شامل ${CUSTOM_ADDONS} نیست"

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
if port_in_use "${HTTP_PORT}"; then
  warn "پورت ${HTTP_PORT} هنوز listen است — ادامه می‌دهیم اما ممکن است سرویس دیگری روی آن باشد"
else
  log "سرویس متوقف شد"
fi

# =============================================================================
step "2) پشتیبان پیش از ارتقا (Q10/NFR-005)"
# =============================================================================
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G1-01" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "SKIP_BACKUP=1"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  BK_OUT="$(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)"
  BK_DUMP="$(echo "${BK_OUT}" | head -n1)"
  if [[ -s "${BK_DUMP:-/nonexistent}" ]]; then
    gate "G1-01" "پشتیبان پیش از ارتقا گرفته شد" "PASS" "$(basename "${BK_DUMP}")"
  else
    gate "G1-01" "پشتیبان پیش از ارتقا گرفته شد" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G1-01" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "ops/backup.sh یافت نشد"
fi

# =============================================================================
step "3) ساخت اسکلت ماژول itr_base (File-First / Force-Replace)"
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
    "name": "ITR Base",
    "summary": "Iranian base infrastructure: validators, Jalali calendar, settings, bypass audit",
    "description": """
ITR Base (Phase 1)
==================
Shared, domain-free foundation of the Iran Trade & Transport ERP.

Contents
--------
* Pure validators (national id / mobile / SHEBA mod-97 / plate) - no Odoo import.
* THE single Jalali calendar engine of the whole project (ADR-001, G18).
  Storage is always Gregorian/UTC, Jalali is display and input only.
* itr.common.settings : single record, four validation kill-switches.
* itr.validation.bypass.log : append only audit trail, delete is impossible.
* itr.validation.service : the guarded layer. Iranian checks run only for
  Iranian nationality / Iranian plates (G13).

Hard rules honoured here
------------------------
* No business domain logic (no trade, no transport, no notification).
* Technical names are ASCII, Persian labels come from i18n only (Q05/G19).
* No hard coded secret, recipient, message or absolute path (Q07/NFR-004).
""",
    "version": "19.0.1.0.0",
    "category": "Localization/Iran",
    "author": "Iran Trade & Transport ERP",
    "maintainer": "Iran Trade & Transport ERP",
    "license": "LGPL-3",
    "depends": ["base"],
    "data": [
        "security/itr_base_groups.xml",
        "security/ir.model.access.csv",
        "security/itr_base_rules.xml",
        "data/itr_common_settings_data.xml",
        "views/itr_common_settings_views.xml",
        "views/itr_validation_bypass_log_views.xml",
        "views/itr_base_menus.xml",
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
"""Install/upgrade hooks for itr_base.

Idempotent by design (NFR-002): running -u twice must not create a second
settings record and must not silently grant a business group to anybody.
"""
import logging

_logger = logging.getLogger(__name__)

ITR_GROUP_XMLIDS = (
    "itr_base.group_itr_settings_manager",
    "itr_base.group_itr_validation_override",
)


def post_init_hook(env):
    settings = env["itr.common.settings"].get_settings()
    _logger.info("itr_base: settings singleton ready (id=%s)", settings.id)
    _assert_admin_is_clean(env)


def _assert_admin_is_clean(env):
    """Q03 guard: Administrator must never hold an ITR group."""
    admin = env.ref("base.user_admin", raise_if_not_found=False)
    if not admin:
        return
    dirty = [xid for xid in ITR_GROUP_XMLIDS if admin.has_group(xid)]
    if dirty:
        _logger.warning(
            "itr_base/Q03 VIOLATION: Administrator holds ITR groups %s - remove them.",
            dirty,
        )
    else:
        _logger.info("itr_base/Q03 OK: Administrator holds no ITR group.")
PYEOF

# ------------------------------------------------------------------ utils --
write_utf8 "${MOD_DIR}/utils/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import validators
from . import jalali
PYEOF

write_utf8 "${MOD_DIR}/utils/validators.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""itr_base.utils.validators - PURE Iranian validators and normalizers.

Design rules
------------
* No Odoo import here. Pure python only, so the very same code can be unit
  tested, reused by every later module and never duplicated (G18).
* These functions never raise a business error: they return a bool or a
  normalized string. Raising the Persian business error is the job of
  models/itr_validation_service.py (the guarded layer).
"""
import re

PERSIAN_DIGITS = "\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9"
ARABIC_DIGITS = "\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669"
LATIN_DIGITS = "0123456789"

_TO_LATIN = str.maketrans(PERSIAN_DIGITS + ARABIC_DIGITS, LATIN_DIGITS + LATIN_DIGITS)
_TO_PERSIAN = str.maketrans(LATIN_DIGITS, PERSIAN_DIGITS)

_ZERO_WIDTH = ("\u200b", "\u200c", "\u200d", "\u200e", "\u200f", "\ufeff")
_DIACRITICS = re.compile("[\u064b-\u065f\u0670]")
_SEPARATORS = re.compile(r"[\s\-_.,/\\|]+")

_MOBILE_RE = re.compile(r"^09\d{9}$")
_SHEBA_RE = re.compile(r"^IR\d{24}$")
# Iranian plate: 2 digits + 1..6 persian letters + 3 digits + 2 digits province
_PLATE_RE = re.compile(
    "^(\\d{2})([\u0621-\u064a\u066e-\u06d3]{1,6})(\\d{3})(\\d{2})$"
)


def cstr(value):
    """None/False safe string cast."""
    if value is None or value is False:
        return ""
    return str(value)


def to_latin_digits(value):
    """Persian/Arabic digits -> latin digits."""
    return cstr(value).translate(_TO_LATIN)


def to_persian_digits(value):
    """Latin digits -> Persian digits (display only)."""
    return cstr(value).translate(_TO_PERSIAN)


def normalize_text(value):
    """Aggressive normalization for Persian text comparison."""
    text = cstr(value)
    for char in _ZERO_WIDTH:
        text = text.replace(char, "")
    text = text.replace("\u00a0", " ")
    text = (
        text.replace("\u064a", "\u06cc")  # arabic yeh -> persian yeh
        .replace("\u0649", "\u06cc")
        .replace("\u0643", "\u06a9")  # arabic kaf -> persian kaf
        .replace("\u0629", "\u0647")  # teh marbuta -> heh
        .replace("\u0640", "")  # tatweel
    )
    text = _DIACRITICS.sub("", text)
    text = to_latin_digits(text)
    return re.sub(r"\s+", " ", text).strip()


# --------------------------------------------------------------- national id
def normalize_national_id(value):
    code = re.sub(r"\D", "", to_latin_digits(value))
    if not code:
        return ""
    if len(code) < 10:
        code = code.zfill(10)
    return code


def is_valid_national_id(value):
    """Iranian national id: 10 digits + official checksum."""
    code = normalize_national_id(value)
    if len(code) != 10 or not code.isdigit():
        return False
    if len(set(code)) == 1:
        return False
    digits = [int(char) for char in code]
    check_digit = digits[9]
    weighted = sum(digits[index] * (10 - index) for index in range(9))
    remainder = weighted % 11
    expected = remainder if remainder < 2 else 11 - remainder
    return check_digit == expected


# ------------------------------------------------------------------- mobile
def normalize_mobile(value):
    digits = re.sub(r"\D", "", to_latin_digits(value))
    if digits.startswith("0098"):
        digits = "0" + digits[4:]
    elif digits.startswith("98") and len(digits) == 12:
        digits = "0" + digits[2:]
    elif len(digits) == 10 and digits.startswith("9"):
        digits = "0" + digits
    return digits


def is_valid_mobile(value):
    return bool(_MOBILE_RE.match(normalize_mobile(value)))


# -------------------------------------------------------------------- sheba
def normalize_sheba(value):
    text = re.sub(r"[^0-9A-Z]", "", to_latin_digits(value).upper())
    if text.isdigit() and len(text) == 24:
        text = "IR" + text
    return text


def is_valid_sheba(value):
    """IBAN mod-97 check restricted to Iranian IR + 24 digits."""
    sheba = normalize_sheba(value)
    if not _SHEBA_RE.match(sheba):
        return False
    rearranged = sheba[4:] + sheba[:4]
    numeric = "".join(
        str(ord(char) - 55) if char.isalpha() else char for char in rearranged
    )
    remainder = 0
    for index in range(0, len(numeric), 7):
        remainder = int(str(remainder) + numeric[index:index + 7]) % 97
    return remainder == 1


def mask_sheba(value, head=4, tail=4, mask="****"):
    """VAL-008 single masking policy for every output: IR93****0872."""
    sheba = normalize_sheba(value)
    if len(sheba) <= head + tail:
        return sheba
    return sheba[:head] + mask + sheba[-tail:]


# -------------------------------------------------------------------- plate
def normalize_plate(value):
    text = normalize_text(value).replace("\u0627\u06cc\u0631\u0627\u0646", " ")
    text = _SEPARATORS.sub(" ", text)
    return re.sub(r"\s+", " ", text).strip()


def plate_parts_ir(value):
    compact = normalize_plate(value).replace(" ", "")
    match = _PLATE_RE.match(compact)
    if not match:
        return None
    return {
        "two": match.group(1),
        "letter": match.group(2),
        "three": match.group(3),
        "province": match.group(4),
    }


def is_valid_iran_plate(value):
    return plate_parts_ir(value) is not None


def canonical_plate_ir(value):
    parts = plate_parts_ir(value)
    if not parts:
        return normalize_plate(value)
    return "%s %s %s %s %s" % (
        parts["two"],
        parts["letter"],
        parts["three"],
        "\u0627\u06cc\u0631\u0627\u0646",
        parts["province"],
    )


# ----------------------------------------------------------------- selftest
def self_test():
    """Pure python self test, callable from tests and from the verify script."""
    failed = []
    checked = 0

    def expect(title, condition):
        nonlocal checked
        checked += 1
        if not condition:
            failed.append(title)

    expect("digits fa->latin", to_latin_digits("\u06f0\u06f9\u06f1\u06f2") == "0912")
    expect("digits ar->latin", to_latin_digits("\u0660\u0669\u0661\u0662") == "0912")
    expect("digits latin->fa", to_persian_digits("0912") == "\u06f0\u06f9\u06f1\u06f2")

    expect("nid valid 1", is_valid_national_id("0084575948"))
    expect("nid valid 2", is_valid_national_id("0013542419"))
    expect("nid valid persian", is_valid_national_id("\u06f0\u06f0\u06f1\u06f3\u06f5\u06f4\u06f2\u06f4\u06f1\u06f9"))
    expect("nid invalid checksum", not is_valid_national_id("0013542418"))
    expect("nid invalid repeated", not is_valid_national_id("1111111111"))
    expect("nid invalid short", not is_valid_national_id("123"))
    expect("nid invalid letters", not is_valid_national_id("abcdefghij"))

    expect("mobile valid", is_valid_mobile("09123456789"))
    expect("mobile valid +98", normalize_mobile("+98 912 345 6789") == "09123456789")
    expect("mobile invalid prefix", not is_valid_mobile("08123456789"))
    expect("mobile invalid length", not is_valid_mobile("0912345678"))

    expect("sheba valid", is_valid_sheba("IR930150000001351800087201"))
    expect("sheba valid spaced", is_valid_sheba("IR93 0150-0000 0135 1800 0872 01"))
    expect("sheba invalid checksum", not is_valid_sheba("IR930150000001351800087202"))
    expect("sheba invalid prefix", not is_valid_sheba("US930150000001351800087201"))
    expect("sheba invalid zeros", not is_valid_sheba("IR000000000000000000000000"))
    expect("sheba mask", mask_sheba("IR930150000001351800087201") == "IR93****7201")

    expect("plate valid compact", is_valid_iran_plate("12\u0628" + "34567"))
    expect("plate valid spaced", is_valid_iran_plate("12 \u0628 345 \u0627\u06cc\u0631\u0627\u0646 67"))
    expect("plate valid persian digits", is_valid_iran_plate("\u06f1\u06f2\u0628\u06f3\u06f4\u06f5\u06f6\u06f7"))
    expect("plate invalid", not is_valid_iran_plate("TR 34 ABC 12"))

    return {"checked": checked, "failed": failed, "ok": not failed}
PYEOF

write_utf8 "${MOD_DIR}/utils/jalali.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""itr_base.utils.jalali - THE single Jalali calendar engine of the project.

ADR-001 / G18
-------------
* Storage is ALWAYS Gregorian (Odoo Date/Datetime, UTC). Jalali is display
  and input only.
* Exactly ONE calendar algorithm may exist in the whole custom addons repo.
  Any second implementation turns Gate 1 red (grep enforced by the phase
  script).

Algorithm: Borkowski / jalaali reference implementation, valid for jalali
years 1178..3177. Pure python, no Odoo import, no external dependency.
"""
import datetime
import re

JALALI_BREAKS = [
    -61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181,
    1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178,
]

JALALI_MONTHS_FA = [
    "\u0641\u0631\u0648\u0631\u062f\u06cc\u0646",
    "\u0627\u0631\u062f\u06cc\u0628\u0647\u0634\u062a",
    "\u062e\u0631\u062f\u0627\u062f",
    "\u062a\u06cc\u0631",
    "\u0645\u0631\u062f\u0627\u062f",
    "\u0634\u0647\u0631\u06cc\u0648\u0631",
    "\u0645\u0647\u0631",
    "\u0622\u0628\u0627\u0646",
    "\u0622\u0630\u0631",
    "\u062f\u06cc",
    "\u0628\u0647\u0645\u0646",
    "\u0627\u0633\u0641\u0646\u062f",
]

# (jalali) <-> (gregorian) anchors used as regression vectors (Nowruz + leap end)
ANCHORS = [
    ((1395, 1, 1), (2016, 3, 20)),
    ((1396, 1, 1), (2017, 3, 21)),
    ((1397, 1, 1), (2018, 3, 21)),
    ((1398, 1, 1), (2019, 3, 21)),
    ((1399, 1, 1), (2020, 3, 20)),
    ((1400, 1, 1), (2021, 3, 21)),
    ((1401, 1, 1), (2022, 3, 21)),
    ((1402, 1, 1), (2023, 3, 21)),
    ((1403, 1, 1), (2024, 3, 20)),
    ((1403, 12, 30), (2025, 3, 20)),
    ((1404, 1, 1), (2025, 3, 21)),
    ((1405, 1, 1), (2026, 3, 21)),
    ((1406, 1, 1), (2027, 3, 21)),
    ((1407, 1, 1), (2028, 3, 20)),
]

_JALALI_TEXT_RE = re.compile(r"^(\d{3,4})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{1,2})")
_PERSIAN_TO_LATIN = str.maketrans(
    "\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9"
    "\u0660\u0661\u0662\u0663\u0664\u0665\u0666\u0667\u0668\u0669",
    "01234567890123456789",
)
_LATIN_TO_PERSIAN = str.maketrans(
    "0123456789",
    "\u06f0\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9",
)


def _trunc_div(numerator, denominator):
    """Integer division truncated toward zero (reference algorithm semantics)."""
    quotient = abs(numerator) // abs(denominator)
    return quotient if (numerator >= 0) == (denominator > 0) else -quotient


def _trunc_mod(numerator, denominator):
    return numerator - _trunc_div(numerator, denominator) * denominator


def _jalali_calendar(jalali_year):
    """Return dict(leap, gy, march) for the given jalali year."""
    gregorian_year = jalali_year + 621
    leap_jalali = -14
    previous_break = JALALI_BREAKS[0]
    jump = 0
    if jalali_year < previous_break or jalali_year >= JALALI_BREAKS[-1]:
        raise ValueError("Jalali year out of supported range: %s" % jalali_year)
    for index in range(1, len(JALALI_BREAKS)):
        current_break = JALALI_BREAKS[index]
        jump = current_break - previous_break
        if jalali_year < current_break:
            break
        leap_jalali += _trunc_div(jump, 33) * 8 + _trunc_div(_trunc_mod(jump, 33), 4)
        previous_break = current_break
    offset = jalali_year - previous_break
    leap_jalali += _trunc_div(offset, 33) * 8 + _trunc_div(_trunc_mod(offset, 33) + 3, 4)
    if _trunc_mod(jump, 33) == 4 and jump - offset == 4:
        leap_jalali += 1
    leap_gregorian = (
        _trunc_div(gregorian_year, 4)
        - _trunc_div((_trunc_div(gregorian_year, 100) + 1) * 3, 4)
        - 150
    )
    march = 20 + leap_jalali - leap_gregorian
    if jump - offset < 6:
        offset = offset - jump + _trunc_div(jump + 4, 33) * 33
    leap = _trunc_mod(_trunc_mod(offset + 1, 33) - 1, 4)
    if leap == -1:
        leap = 4
    return {"leap": leap, "gy": gregorian_year, "march": march}


def _gregorian_to_jdn(gy, gm, gd):
    day_number = (
        _trunc_div((gy + _trunc_div(gm - 8, 6) + 100100) * 1461, 4)
        + _trunc_div(153 * _trunc_mod(gm + 9, 12) + 2, 5)
        + gd
        - 34840408
    )
    return day_number - _trunc_div(_trunc_div(gy + 100100 + _trunc_div(gm - 8, 6), 100) * 3, 4) + 752


def _jdn_to_gregorian(jdn):
    value = (
        4 * jdn
        + 139361631
        + _trunc_div(_trunc_div(4 * jdn + 183187720, 146097) * 3, 4) * 4
        - 3908
    )
    helper = _trunc_div(_trunc_mod(value, 1461), 4) * 5 + 308
    gd = _trunc_div(_trunc_mod(helper, 153), 5) + 1
    gm = _trunc_mod(_trunc_div(helper, 153), 12) + 1
    gy = _trunc_div(value, 1461) - 100100 + _trunc_div(8 - gm, 6)
    return gy, gm, gd


def _jalali_to_jdn(jy, jm, jd):
    calendar = _jalali_calendar(jy)
    return (
        _gregorian_to_jdn(calendar["gy"], 3, calendar["march"])
        + (jm - 1) * 31
        - _trunc_div(jm, 7) * (jm - 7)
        + jd
        - 1
    )


def _jdn_to_jalali(jdn):
    gy = _jdn_to_gregorian(jdn)[0]
    jy = gy - 621
    calendar = _jalali_calendar(jy)
    jdn_first_farvardin = _gregorian_to_jdn(gy, 3, calendar["march"])
    offset = jdn - jdn_first_farvardin
    if offset >= 0:
        if offset <= 185:
            return jy, _trunc_div(offset, 31) + 1, _trunc_mod(offset, 31) + 1
        offset -= 186
    else:
        jy -= 1
        offset += 179
        if calendar["leap"] == 1:
            offset += 1
    return jy, 7 + _trunc_div(offset, 30), _trunc_mod(offset, 30) + 1


# ------------------------------------------------------------------ public
def gregorian_to_jalali(gy, gm, gd):
    return _jdn_to_jalali(_gregorian_to_jdn(gy, gm, gd))


def jalali_to_gregorian(jy, jm, jd):
    return _jdn_to_gregorian(_jalali_to_jdn(jy, jm, jd))


def is_leap_jalali_year(jalali_year):
    return _jalali_calendar(jalali_year)["leap"] == 0


def jalali_month_length(jalali_year, jalali_month):
    if jalali_month <= 6:
        return 31
    if jalali_month <= 11:
        return 30
    return 30 if is_leap_jalali_year(jalali_year) else 29


def as_date(value):
    """Accept date / datetime / 'YYYY-MM-DD[ HH:MM:SS]' and return a date."""
    if not value:
        return None
    if isinstance(value, datetime.datetime):
        return value.date()
    if isinstance(value, datetime.date):
        return value
    text = str(value).strip().split(" ")[0].split("T")[0]
    try:
        year, month, day = (int(part) for part in text.split("-"))
        return datetime.date(year, month, day)
    except (ValueError, TypeError):
        return None


def to_jalali_str(value, sep="/", persian_digits=False):
    date_value = as_date(value)
    if not date_value:
        return ""
    jy, jm, jd = gregorian_to_jalali(date_value.year, date_value.month, date_value.day)
    text = "%04d%s%02d%s%02d" % (jy, sep, jm, sep, jd)
    return text.translate(_LATIN_TO_PERSIAN) if persian_digits else text


def to_jalali_long_fa(value):
    date_value = as_date(value)
    if not date_value:
        return ""
    jy, jm, jd = gregorian_to_jalali(date_value.year, date_value.month, date_value.day)
    text = "%d %s %d" % (jd, JALALI_MONTHS_FA[jm - 1], jy)
    return text.translate(_LATIN_TO_PERSIAN)


def parse_jalali(text):
    """'1404/01/01' or persian digits -> datetime.date (gregorian) or None."""
    if not text:
        return None
    normalized = str(text).strip().translate(_PERSIAN_TO_LATIN)
    match = _JALALI_TEXT_RE.match(normalized)
    if not match:
        return None
    jy, jm, jd = (int(part) for part in match.groups())
    if not 1200 <= jy <= 1600 or not 1 <= jm <= 12:
        return None
    if not 1 <= jd <= jalali_month_length(jy, jm):
        return None
    gy, gm, gd = jalali_to_gregorian(jy, jm, jd)
    return datetime.date(gy, gm, gd)


def boundary_dates(start_jy=1390, end_jy=1425):
    """Nowruz / month edges / 29-30 esfand / leap ends -> >= 50 dates."""
    dates = []
    for jalali_year in range(start_jy, end_jy + 1):
        dates.extend([
            (jalali_year, 1, 1),
            (jalali_year, 6, 31),
            (jalali_year, 7, 1),
            (jalali_year, 11, 30),
            (jalali_year, 12, 29),
        ])
        if is_leap_jalali_year(jalali_year):
            dates.append((jalali_year, 12, 30))
    return dates


def roundtrip_selftest(start_jy=1390, end_jy=1425):
    """Two way conversion test on every boundary date + every anchor."""
    failed = []
    dates = boundary_dates(start_jy, end_jy)
    for jy, jm, jd in dates:
        gy, gm, gd = jalali_to_gregorian(jy, jm, jd)
        back = gregorian_to_jalali(gy, gm, gd)
        if back != (jy, jm, jd):
            failed.append("j2g2j %s -> %s -> %s" % ((jy, jm, jd), (gy, gm, gd), back))
        forward = jalali_to_gregorian(*back)
        if forward != (gy, gm, gd):
            failed.append("g2j2g %s -> %s" % ((gy, gm, gd), forward))
    for jalali, gregorian in ANCHORS:
        if jalali_to_gregorian(*jalali) != gregorian:
            failed.append("anchor j2g %s != %s" % (jalali, gregorian))
        if gregorian_to_jalali(*gregorian) != jalali:
            failed.append("anchor g2j %s != %s" % (gregorian, jalali))
    return {
        "checked": len(dates),
        "anchors": len(ANCHORS),
        "failed": failed,
        "ok": not failed,
    }
PYEOF

# ----------------------------------------------------------------- models --
write_utf8 "${MOD_DIR}/models/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import itr_validation_bypass_log
from . import itr_common_settings
from . import itr_validation_service
PYEOF

write_utf8 "${MOD_DIR}/models/itr_validation_bypass_log.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Append only audit trail of every skipped / bypassed Iranian validation.

VAL-006 / VAL-007: turning a validation switch off is never silent.
The record can never be deleted (not even by the superuser) and no group has
write or unlink access.
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

CHECK_KINDS = [
    ("national_id", "National ID"),
    ("mobile", "Mobile number"),
    ("sheba", "SHEBA"),
    ("plate", "Vehicle plate"),
    ("settings", "Settings switch change"),
]


class ItrValidationBypassLog(models.Model):
    _name = "itr.validation.bypass.log"
    _description = "Iran Validation Bypass Log"
    _order = "id desc"

    check_kind = fields.Selection(
        CHECK_KINDS, string="Check kind", required=True, readonly=True, index=True
    )
    raw_value = fields.Char(string="Submitted value", readonly=True)
    res_model = fields.Char(string="Reference model", readonly=True, index=True)
    res_id = fields.Integer(string="Reference id", readonly=True)
    reason = fields.Text(string="Reason", required=True, readonly=True)
    acted_by_id = fields.Many2one(
        "res.users",
        string="Acted by",
        required=True,
        readonly=True,
        index=True,
        ondelete="restrict",
        default=lambda self: self.env.user,
    )
    acted_on = fields.Datetime(
        string="Acted on", required=True, readonly=True, default=fields.Datetime.now
    )

    @api.depends("check_kind", "acted_on")
    def _compute_display_name(self):
        labels = dict(CHECK_KINDS)
        for record in self:
            record.display_name = "%s / %s" % (
                labels.get(record.check_kind, record.check_kind or "-"),
                record.acted_on or "-",
            )

    def unlink(self):
        raise UserError(
            _("Validation bypass log records are append-only and cannot be deleted.")
        )
PYEOF

write_utf8 "${MOD_DIR}/models/itr_common_settings.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Single-record settings of the Iranian base layer.

Four independent kill-switches (VAL-006). Switching one OFF requires:
  * membership of group_itr_validation_override (VAL-007)
  * a mandatory free text reason
  * an automatic, undeletable audit row in itr.validation.bypass.log
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

DEFAULT_SETTINGS_NAME = "ITR Common Settings"

SWITCH_FIELDS = {
    "enable_national_id_check": "national_id",
    "enable_mobile_check": "mobile",
    "enable_sheba_check": "sheba",
    "enable_plate_check": "plate",
}


class ItrCommonSettings(models.Model):
    _name = "itr.common.settings"
    _description = "Iran Base Common Settings"
    _rec_name = "name"

    name = fields.Char(string="Name", required=True, default=DEFAULT_SETTINGS_NAME)
    enable_national_id_check = fields.Boolean(
        string="Validate Iranian national ID", default=True
    )
    enable_mobile_check = fields.Boolean(
        string="Validate Iranian mobile number", default=True
    )
    enable_sheba_check = fields.Boolean(string="Validate SHEBA number", default=True)
    enable_plate_check = fields.Boolean(
        string="Validate Iranian plate format", default=True
    )
    sheba_mask_enabled = fields.Boolean(
        string="Mask SHEBA on every output", default=True
    )
    switch_change_reason = fields.Text(
        string="Reason of the last switch change",
        help="Mandatory whenever a validation switch is turned off.",
    )
    default_country_code = fields.Char(
        string="Default country code", default="IR", readonly=True
    )
    calendar_policy = fields.Char(
        string="Calendar policy",
        default="Storage=Gregorian/UTC, Display=Jalali (ADR-001)",
        readonly=True,
    )
    note = fields.Text(string="Notes")

    @api.constrains("name")
    def _check_single_record(self):
        if self.search_count([]) > 1:
            raise ValidationError(
                _("Only one Iran base settings record is allowed (single record model).")
            )

    @api.model
    def get_settings(self):
        """The one and only entry point to the settings record."""
        settings = self.env.ref(
            "itr_base.itr_common_settings_default", raise_if_not_found=False
        )
        if settings:
            return settings
        settings = self.search([], limit=1)
        if settings:
            return settings
        # bootstrap of the singleton itself, never a business decision:
        return self.sudo().create({"name": DEFAULT_SETTINGS_NAME})  # ITR-SUDO-OK

    def action_open_settings(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "res_model": self._name,
            "res_id": self.id,
            "view_mode": "form",
            "target": "current",
        }

    def write(self, vals):
        changes = []
        for record in self:
            for field_name, kind in SWITCH_FIELDS.items():
                if field_name not in vals:
                    continue
                old_value = bool(record[field_name])
                new_value = bool(vals[field_name])
                if old_value != new_value:
                    changes.append((record, field_name, kind, old_value, new_value))
        if changes:
            self._check_switch_permission()
            reason = (vals.get("switch_change_reason") or "").strip()
            if not reason and any(change[4] is False for change in changes):
                raise ValidationError(
                    _(
                        "Turning an Iranian validation check off requires a mandatory "
                        "reason in the 'Reason of the last switch change' field."
                    )
                )
        result = super().write(vals)
        for record, field_name, kind, old_value, new_value in changes:
            record._log_switch_change(field_name, kind, old_value, new_value)
        return result

    def _check_switch_permission(self):
        if self.env.su:
            return
        if not self.env.user.has_group("itr_base.group_itr_validation_override"):
            raise UserError(
                _(
                    "Only members of the 'Validation Override' group may change the "
                    "Iranian validation switches."
                )
            )

    def _log_switch_change(self, field_name, kind, old_value, new_value):
        self.ensure_one()
        reason = (self.switch_change_reason or "").strip() or _("No reason provided")
        message = _(
            "Validation switch %(field)s set to %(state)s by %(user)s. Reason: %(reason)s",
            field=field_name,
            state="ON" if new_value else "OFF",
            user=self.env.user.display_name,
            reason=reason,
        )
        self.env["itr.validation.bypass.log"].create({
            "check_kind": "settings",
            "raw_value": "%s:%s->%s" % (kind, int(old_value), int(new_value)),
            "res_model": self._name,
            "res_id": self.id,
            "reason": message,
        })
PYEOF

write_utf8 "${MOD_DIR}/models/itr_validation_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""The guarded layer (checklist 1.7).

Every later module (itr_core, itr_transport, ...) must call THIS service and
never re-implement a check:

    self.env['itr.validation.service'].check_national_id(value, nationality)

Guarantees
----------
* Iranian-only checks are skipped for foreign people / foreign plates without
  raising anything (G13).
* When a check is switched off, the value is accepted AND an undeletable audit
  row is written (VAL-006). Never silent.
* SHEBA values are always masked before they are written into any log
  (NFR-007).
"""
import logging

from odoo import _, api, models
from odoo.exceptions import ValidationError

from ..utils import jalali, validators

_logger = logging.getLogger(__name__)

NATIONALITY_IRANIAN = "ir"
PLATE_TYPE_IRANIAN = "ir"

KIND_TO_FIELD = {
    "national_id": "enable_national_id_check",
    "mobile": "enable_mobile_check",
    "sheba": "enable_sheba_check",
    "plate": "enable_plate_check",
}


class ItrValidationService(models.AbstractModel):
    _name = "itr.validation.service"
    _description = "Iran Validation Service"

    # ------------------------------------------------------------- settings
    @api.model
    def settings(self):
        return self.env["itr.common.settings"].get_settings()

    @api.model
    def is_check_enabled(self, kind):
        field_name = KIND_TO_FIELD.get(kind)
        if not field_name:
            return True
        settings = self.settings()
        return bool(settings[field_name]) if settings else True

    # ------------------------------------------------------------------ log
    @api.model
    def log_bypass(self, kind, raw_value, res_model=None, res_id=None, reason=None):
        """Never silent (VAL-006). Never breaks the caller."""
        safe_value = (
            validators.mask_sheba(raw_value)
            if kind == "sheba"
            else validators.cstr(raw_value)[:140]
        )
        message = reason or _(
            "Check %(kind)s is switched off in the Iran base settings.", kind=kind
        )
        try:
            return self.env["itr.validation.bypass.log"].create({
                "check_kind": kind,
                "raw_value": safe_value,
                "res_model": res_model,
                "res_id": res_id or 0,
                "reason": message,
            })
        except Exception:  # pragma: no cover - audit must never break business
            _logger.exception(
                "itr_base: could not write bypass log for kind=%s model=%s id=%s",
                kind, res_model, res_id,
            )
            return self.env["itr.validation.bypass.log"]

    # --------------------------------------------------------------- checks
    @api.model
    def check_national_id(
        self, value, nationality=NATIONALITY_IRANIAN, res_model=None, res_id=None
    ):
        if not value:
            return ""
        if (nationality or NATIONALITY_IRANIAN) != NATIONALITY_IRANIAN:
            # G13: foreign people are identified by passport, never by national id
            return validators.to_latin_digits(value).strip()
        normalized = validators.normalize_national_id(value)
        if not self.is_check_enabled("national_id"):
            self.log_bypass("national_id", value, res_model, res_id)
            return normalized
        if not validators.is_valid_national_id(normalized):
            raise ValidationError(
                _("Invalid Iranian national ID: %(value)s", value=value)
            )
        return normalized

    @api.model
    def check_mobile(self, value, res_model=None, res_id=None):
        if not value:
            return ""
        normalized = validators.normalize_mobile(value)
        if not self.is_check_enabled("mobile"):
            self.log_bypass("mobile", value, res_model, res_id)
            return normalized
        if not validators.is_valid_mobile(normalized):
            raise ValidationError(
                _("Invalid Iranian mobile number: %(value)s", value=value)
            )
        return normalized

    @api.model
    def check_sheba(self, value, res_model=None, res_id=None):
        if not value:
            return ""
        normalized = validators.normalize_sheba(value)
        if not self.is_check_enabled("sheba"):
            self.log_bypass("sheba", value, res_model, res_id)
            return normalized
        if not validators.is_valid_sheba(normalized):
            raise ValidationError(
                _("Invalid SHEBA number: %(value)s", value=validators.mask_sheba(value))
            )
        return normalized

    @api.model
    def check_plate(
        self, value, plate_type=PLATE_TYPE_IRANIAN, res_model=None, res_id=None
    ):
        if not value:
            return ""
        if (plate_type or PLATE_TYPE_IRANIAN) != PLATE_TYPE_IRANIAN:
            # G13: transit / temporary plates have no Iranian format
            return validators.normalize_plate(value)
        normalized = validators.normalize_plate(value)
        if not self.is_check_enabled("plate"):
            self.log_bypass("plate", value, res_model, res_id)
            return normalized
        if not validators.is_valid_iran_plate(normalized):
            raise ValidationError(
                _("Invalid Iranian vehicle plate: %(value)s", value=value)
            )
        return validators.canonical_plate_ir(normalized)

    # --------------------------------------------------------------- output
    @api.model
    def mask_sheba(self, value):
        """VAL-008: one masking policy for report, excel, print and API."""
        settings = self.settings()
        if settings and not settings.sheba_mask_enabled:
            return validators.normalize_sheba(value)
        return validators.mask_sheba(value)

    @api.model
    def to_persian_digits(self, value):
        return validators.to_persian_digits(value)

    @api.model
    def to_latin_digits(self, value):
        return validators.to_latin_digits(value)

    # ------------------------------------------------------------- calendar
    @api.model
    def to_jalali(self, value, sep="/", persian_digits=False):
        return jalali.to_jalali_str(value, sep=sep, persian_digits=persian_digits)

    @api.model
    def to_jalali_long(self, value):
        return jalali.to_jalali_long_fa(value)

    @api.model
    def parse_jalali(self, text):
        return jalali.parse_jalali(text)

    # ------------------------------------------------------------- selftest
    @api.model
    def jalali_selftest(self, start_jy=1390, end_jy=1425):
        return jalali.roundtrip_selftest(start_jy, end_jy)

    @api.model
    def validators_selftest(self):
        return validators.self_test()
PYEOF

# --------------------------------------------------------------- security --
write_utf8 "${MOD_DIR}/security/itr_base_groups.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- Odoo 19: res.groups.category_id no longer exists, groups are
             attached to a res.groups.privilege which points to the category. -->
        <record id="module_category_itr" model="ir.module.category">
            <field name="name">Iran Trade &amp; Transport</field>
            <field name="description">Iran Trade &amp; Transport ERP</field>
            <field name="sequence">90</field>
        </record>

        <record id="privilege_itr_base" model="res.groups.privilege">
            <field name="name">Iran Base Infrastructure</field>
            <field name="description">Validators, Jalali calendar and base settings</field>
            <field name="category_id" ref="itr_base.module_category_itr"/>
            <field name="sequence">10</field>
        </record>

        <record id="group_itr_settings_manager" model="res.groups">
            <field name="name">Settings Manager</field>
            <field name="privilege_id" ref="itr_base.privilege_itr_base"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">May read and edit the Iran base settings record.</field>
        </record>

        <record id="group_itr_validation_override" model="res.groups">
            <field name="name">Validation Override</field>
            <field name="privilege_id" ref="itr_base.privilege_itr_base"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">May switch an Iranian validation check off, with a mandatory reason (VAL-007).</field>
        </record>

    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/security/ir.model.access.csv" <<'CSVEOF'
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_itr_common_settings_user,itr.common.settings user read,model_itr_common_settings,base.group_user,1,0,0,0
access_itr_common_settings_manager,itr.common.settings manager,model_itr_common_settings,itr_base.group_itr_settings_manager,1,1,0,0
access_itr_common_settings_override,itr.common.settings override,model_itr_common_settings,itr_base.group_itr_validation_override,1,1,0,0
access_itr_validation_bypass_log_user,itr.validation.bypass.log user,model_itr_validation_bypass_log,base.group_user,1,0,1,0
access_itr_validation_bypass_log_manager,itr.validation.bypass.log manager,model_itr_validation_bypass_log,itr_base.group_itr_settings_manager,1,0,1,0
access_itr_validation_bypass_log_override,itr.validation.bypass.log override,model_itr_validation_bypass_log,itr_base.group_itr_validation_override,1,0,1,0
CSVEOF

write_utf8 "${MOD_DIR}/security/itr_base_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- A normal internal user only sees the bypass rows he created.
             Settings Manager / Validation Override see everything (rules of
             the groups a user belongs to are OR-ed). -->
        <record id="rule_itr_bypass_log_own" model="ir.rule">
            <field name="name">Validation bypass log: own rows only</field>
            <field name="model_id" ref="itr_base.model_itr_validation_bypass_log"/>
            <field name="domain_force">[('acted_by_id', '=', user.id)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_itr_bypass_log_all" model="ir.rule">
            <field name="name">Validation bypass log: full audit access</field>
            <field name="model_id" ref="itr_base.model_itr_validation_bypass_log"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('itr_base.group_itr_settings_manager')), (4, ref('itr_base.group_itr_validation_override'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${MOD_DIR}/data/itr_common_settings_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- noupdate=1 : an upgrade never resets what the customer configured. -->
    <data noupdate="1">
        <record id="itr_common_settings_default" model="itr.common.settings">
            <field name="name">ITR Common Settings</field>
            <field name="enable_national_id_check" eval="True"/>
            <field name="enable_mobile_check" eval="True"/>
            <field name="enable_sheba_check" eval="True"/>
            <field name="enable_plate_check" eval="True"/>
            <field name="sheba_mask_enabled" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${MOD_DIR}/views/itr_common_settings_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_common_settings_form" model="ir.ui.view">
        <field name="name">itr.common.settings.form</field>
        <field name="model">itr.common.settings</field>
        <field name="arch" type="xml">
            <form string="Iran Base Settings">
                <sheet>
                    <div class="oe_title">
                        <h1><field name="name" readonly="1"/></h1>
                    </div>
                    <group>
                        <group string="Iranian validation switches">
                            <field name="enable_national_id_check"/>
                            <field name="enable_mobile_check"/>
                            <field name="enable_sheba_check"/>
                            <field name="enable_plate_check"/>
                            <field name="sheba_mask_enabled"/>
                        </group>
                        <group string="Locked policy">
                            <field name="default_country_code"/>
                            <field name="calendar_policy"/>
                        </group>
                    </group>
                    <group string="Mandatory audit reason">
                        <field name="switch_change_reason" nolabel="1"
                               placeholder="Mandatory when a validation switch is turned off"/>
                    </group>
                    <group string="Notes">
                        <field name="note" nolabel="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_common_settings_list" model="ir.ui.view">
        <field name="name">itr.common.settings.list</field>
        <field name="model">itr.common.settings</field>
        <field name="arch" type="xml">
            <list string="Iran Base Settings">
                <field name="name"/>
                <field name="enable_national_id_check"/>
                <field name="enable_mobile_check"/>
                <field name="enable_sheba_check"/>
                <field name="enable_plate_check"/>
            </list>
        </field>
    </record>

    <record id="action_itr_common_settings" model="ir.actions.act_window">
        <field name="name">Iran Base Settings</field>
        <field name="res_model">itr.common.settings</field>
        <field name="view_mode">form</field>
        <field name="res_id" eval="ref('itr_base.itr_common_settings_default')"/>
        <field name="target">current</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_validation_bypass_log_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_validation_bypass_log_list" model="ir.ui.view">
        <field name="name">itr.validation.bypass.log.list</field>
        <field name="model">itr.validation.bypass.log</field>
        <field name="arch" type="xml">
            <list string="Validation Bypass Log" create="false" edit="false" delete="false">
                <field name="acted_on"/>
                <field name="check_kind"/>
                <field name="raw_value"/>
                <field name="res_model"/>
                <field name="res_id"/>
                <field name="acted_by_id"/>
                <field name="reason"/>
            </list>
        </field>
    </record>

    <record id="view_itr_validation_bypass_log_form" model="ir.ui.view">
        <field name="name">itr.validation.bypass.log.form</field>
        <field name="model">itr.validation.bypass.log</field>
        <field name="arch" type="xml">
            <form string="Validation Bypass Log" create="false" edit="false" delete="false">
                <sheet>
                    <group>
                        <group>
                            <field name="check_kind"/>
                            <field name="raw_value"/>
                            <field name="acted_by_id"/>
                            <field name="acted_on"/>
                        </group>
                        <group>
                            <field name="res_model"/>
                            <field name="res_id"/>
                        </group>
                    </group>
                    <group string="Reason">
                        <field name="reason" nolabel="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_validation_bypass_log_search" model="ir.ui.view">
        <field name="name">itr.validation.bypass.log.search</field>
        <field name="model">itr.validation.bypass.log</field>
        <field name="arch" type="xml">
            <search string="Validation Bypass Log">
                <field name="check_kind"/>
                <field name="acted_by_id"/>
                <field name="res_model"/>
                <filter name="group_kind" string="Check kind" context="{'group_by': 'check_kind'}"/>
                <filter name="group_user" string="User" context="{'group_by': 'acted_by_id'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_validation_bypass_log" model="ir.actions.act_window">
        <field name="name">Validation Bypass Log</field>
        <field name="res_model">itr.validation.bypass.log</field>
        <field name="view_mode">list,form</field>
        <field name="context">{}</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_base_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_root"
              name="Iran Base"
              sequence="90"
              groups="itr_base.group_itr_settings_manager,itr_base.group_itr_validation_override"/>

    <menuitem id="menu_itr_configuration"
              name="Configuration"
              parent="menu_itr_root"
              sequence="10"/>

    <menuitem id="menu_itr_common_settings"
              name="Iran Base Settings"
              parent="menu_itr_configuration"
              action="action_itr_common_settings"
              sequence="10"
              groups="itr_base.group_itr_settings_manager"/>

    <menuitem id="menu_itr_validation_bypass_log"
              name="Validation Bypass Log"
              parent="menu_itr_configuration"
              action="action_itr_validation_bypass_log"
              sequence="20"/>
</odoo>
XMLEOF

# -------------------------------------------------------------------- i18n --
write_utf8 "${MOD_DIR}/i18n/fa_IR.po" <<'POEOF'
# Translation of Odoo Server - module itr_base.
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

#. module: itr_base
#: model:ir.model,name:itr_base.model_itr_common_settings
msgid "Iran Base Common Settings"
msgstr "تنظیمات پایهٔ ایران"

#. module: itr_base
#: model:ir.model,name:itr_base.model_itr_validation_bypass_log
msgid "Iran Validation Bypass Log"
msgstr "دفتر عبور از اعتبارسنجی"

#. module: itr_base
#: model:ir.model,name:itr_base.model_itr_validation_service
msgid "Iran Validation Service"
msgstr "سرویس اعتبارسنجی ایران"

#. module: itr_base
#: model:ir.module.category,name:itr_base.module_category_itr
msgid "Iran Trade & Transport"
msgstr "بازرگانی و حمل‌ونقل ایران"

#. module: itr_base
#: model:res.groups.privilege,name:itr_base.privilege_itr_base
msgid "Iran Base Infrastructure"
msgstr "زیرساخت پایهٔ ایران"

#. module: itr_base
#: model:res.groups,name:itr_base.group_itr_settings_manager
msgid "Settings Manager"
msgstr "مدیر تنظیمات"

#. module: itr_base
#: model:res.groups,name:itr_base.group_itr_validation_override
msgid "Validation Override"
msgstr "عبور از اعتبارسنجی"

#. module: itr_base
#: model:ir.ui.menu,name:itr_base.menu_itr_root
msgid "Iran Base"
msgstr "زیرساخت ایران"

#. module: itr_base
#: model:ir.ui.menu,name:itr_base.menu_itr_configuration
msgid "Configuration"
msgstr "پیکربندی"

#. module: itr_base
#: model:ir.actions.act_window,name:itr_base.action_itr_common_settings
#: model:ir.ui.menu,name:itr_base.menu_itr_common_settings
msgid "Iran Base Settings"
msgstr "تنظیمات پایهٔ ایران"

#. module: itr_base
#: model:ir.actions.act_window,name:itr_base.action_itr_validation_bypass_log
#: model:ir.ui.menu,name:itr_base.menu_itr_validation_bypass_log
msgid "Validation Bypass Log"
msgstr "دفتر عبور از اعتبارسنجی"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__name
msgid "Name"
msgstr "نام"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__enable_national_id_check
msgid "Validate Iranian national ID"
msgstr "اعتبارسنجی کد ملی ایرانی فعال باشد"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__enable_mobile_check
msgid "Validate Iranian mobile number"
msgstr "اعتبارسنجی شمارهٔ موبایل ایران فعال باشد"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__enable_sheba_check
msgid "Validate SHEBA number"
msgstr "اعتبارسنجی شمارهٔ شبا فعال باشد"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__enable_plate_check
msgid "Validate Iranian plate format"
msgstr "اعتبارسنجی قالب پلاک ایرانی فعال باشد"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__sheba_mask_enabled
msgid "Mask SHEBA on every output"
msgstr "ماسک‌کردن شبا در همهٔ خروجی‌ها"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__switch_change_reason
msgid "Reason of the last switch change"
msgstr "دلیل آخرین تغییر کلید سنجه"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__default_country_code
msgid "Default country code"
msgstr "کد کشور پیش‌فرض"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__calendar_policy
msgid "Calendar policy"
msgstr "قاعدهٔ تقویم"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_common_settings__note
msgid "Notes"
msgstr "یادداشت"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__check_kind
msgid "Check kind"
msgstr "نوع سنجه"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__raw_value
msgid "Submitted value"
msgstr "مقدار ورودی"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__res_model
msgid "Reference model"
msgstr "مدل سند مرجع"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__res_id
msgid "Reference id"
msgstr "شناسهٔ سند مرجع"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__reason
msgid "Reason"
msgstr "دلیل"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__acted_by_id
msgid "Acted by"
msgstr "کاربر اقدام‌کننده"

#. module: itr_base
#: model:ir.model.fields,field_description:itr_base.field_itr_validation_bypass_log__acted_on
msgid "Acted on"
msgstr "زمان اقدام"

#. module: itr_base
#: model:ir.model.fields.selection,name:itr_base.selection__itr_validation_bypass_log__check_kind__national_id
msgid "National ID"
msgstr "کد ملی"

#. module: itr_base
#: model:ir.model.fields.selection,name:itr_base.selection__itr_validation_bypass_log__check_kind__mobile
msgid "Mobile number"
msgstr "شمارهٔ موبایل"

#. module: itr_base
#: model:ir.model.fields.selection,name:itr_base.selection__itr_validation_bypass_log__check_kind__sheba
msgid "SHEBA"
msgstr "شبا"

#. module: itr_base
#: model:ir.model.fields.selection,name:itr_base.selection__itr_validation_bypass_log__check_kind__plate
msgid "Vehicle plate"
msgstr "پلاک خودرو"

#. module: itr_base
#: model:ir.model.fields.selection,name:itr_base.selection__itr_validation_bypass_log__check_kind__settings
msgid "Settings switch change"
msgstr "تغییر کلید تنظیمات"

#. module: itr_base
#: model_terms:ir.ui.view,arch_db:itr_base.view_itr_common_settings_form
msgid "Iranian validation switches"
msgstr "کلیدهای اعتبارسنجی ایرانی"

#. module: itr_base
#: model_terms:ir.ui.view,arch_db:itr_base.view_itr_common_settings_form
msgid "Locked policy"
msgstr "سیاست قفل‌شده"

#. module: itr_base
#: model_terms:ir.ui.view,arch_db:itr_base.view_itr_common_settings_form
msgid "Mandatory audit reason"
msgstr "دلیل اجباری برای ممیزی"

#. module: itr_base
#: model_terms:ir.ui.view,arch_db:itr_base.view_itr_common_settings_form
msgid "Mandatory when a validation switch is turned off"
msgstr "هنگام خاموش‌کردن هر سنجه، ثبت دلیل اجباری است"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_service.py:0
#, python-format
msgid "Invalid Iranian national ID: %(value)s"
msgstr "کد ملی ایرانی نامعتبر است: %(value)s"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_service.py:0
#, python-format
msgid "Invalid Iranian mobile number: %(value)s"
msgstr "شمارهٔ موبایل ایران نامعتبر است: %(value)s"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_service.py:0
#, python-format
msgid "Invalid SHEBA number: %(value)s"
msgstr "شمارهٔ شبا نامعتبر است: %(value)s"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_service.py:0
#, python-format
msgid "Invalid Iranian vehicle plate: %(value)s"
msgstr "پلاک ایرانی نامعتبر است: %(value)s"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_service.py:0
#, python-format
msgid "Check %(kind)s is switched off in the Iran base settings."
msgstr "سنجهٔ %(kind)s در تنظیمات پایهٔ ایران خاموش است."

#. module: itr_base
#: code:addons/itr_base/models/itr_common_settings.py:0
#, python-format
msgid "Only one Iran base settings record is allowed (single record model)."
msgstr "فقط یک رکورد تنظیمات پایهٔ ایران مجاز است (مدل تک‌رکوردی)."

#. module: itr_base
#: code:addons/itr_base/models/itr_common_settings.py:0
#, python-format
msgid ""
"Turning an Iranian validation check off requires a mandatory reason in the "
"'Reason of the last switch change' field."
msgstr ""
"خاموش‌کردن هر سنجهٔ اعتبارسنجی ایرانی بدون ثبت دلیل اجباری در فیلد «دلیل آخرین "
"تغییر کلید سنجه» ممکن نیست."

#. module: itr_base
#: code:addons/itr_base/models/itr_common_settings.py:0
#, python-format
msgid ""
"Only members of the 'Validation Override' group may change the Iranian "
"validation switches."
msgstr ""
"فقط اعضای گروه «عبور از اعتبارسنجی» مجاز به تغییر کلیدهای اعتبارسنجی ایرانی هستند."

#. module: itr_base
#: code:addons/itr_base/models/itr_common_settings.py:0
#, python-format
msgid "Validation switch %(field)s set to %(state)s by %(user)s. Reason: %(reason)s"
msgstr "کلید سنجهٔ %(field)s توسط %(user)s به وضعیت %(state)s تغییر کرد. دلیل: %(reason)s"

#. module: itr_base
#: code:addons/itr_base/models/itr_common_settings.py:0
#, python-format
msgid "No reason provided"
msgstr "دلیلی ثبت نشده است"

#. module: itr_base
#: code:addons/itr_base/models/itr_validation_bypass_log.py:0
#, python-format
msgid "Validation bypass log records are append-only and cannot be deleted."
msgstr "رکوردهای دفتر عبور از اعتبارسنجی فقط افزودنی هستند و حذف نمی‌شوند."
POEOF
cp -f "${MOD_DIR}/i18n/fa_IR.po" "${MOD_DIR}/i18n/fa.po"

# ------------------------------------------------------------------ tests --
write_utf8 "${MOD_DIR}/tests/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import common
from . import test_validators
from . import test_jalali
from . import test_settings_bypass
PYEOF

write_utf8 "${MOD_DIR}/tests/common.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Shared test helper.

G01: no business assertion is ever made with Administrator / superuser.
Users are created in setUpClass (environment setup, not business proof) and
every assertion runs with_user(real user).
"""
from odoo.tests import TransactionCase


class ItrBaseCase(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        users_model = cls.env["res.users"]
        # Odoo 19 renamed res.users.groups_id -> group_ids ; stay tolerant.
        cls.group_field = "group_ids" if "group_ids" in users_model._fields else "groups_id"
        cls.settings = cls.env["itr.common.settings"].get_settings()

    @classmethod
    def _itr_create_user(cls, login, group_xmlids=()):
        groups = cls.env.ref("base.group_user")
        for xmlid in group_xmlids:
            groups |= cls.env.ref(xmlid)
        return cls.env["res.users"].create({
            "name": "TEST %s" % login,
            "login": login,
            "email": "%s@test.invalid" % login,
            cls.group_field: [(6, 0, groups.ids)],
        })
PYEOF

write_utf8 "${MOD_DIR}/tests/test_validators.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import ValidationError
from odoo.tests import tagged

from odoo.addons.itr_base.utils import validators

from .common import ItrBaseCase


@tagged("post_install", "-at_install", "itr_base")
class TestItrValidators(ItrBaseCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.operator = cls._itr_create_user("test_itr_operator")
        cls.service = cls.env["itr.validation.service"].with_user(cls.operator)

    # ------------------------------------------------------------ national id
    def test_10_national_id_positive(self):
        self.assertEqual(self.service.check_national_id("0084575948"), "0084575948")
        self.assertEqual(
            self.service.check_national_id("\u06f0\u06f0\u06f1\u06f3\u06f5\u06f4\u06f2\u06f4\u06f1\u06f9"),
            "0013542419",
        )

    def test_11_national_id_negative(self):
        for bad in ("1234567890", "0013542418", "1111111111", "123", "abcdefghij"):
            with self.subTest(value=bad), self.assertRaises(ValidationError):
                self.service.check_national_id(bad)

    def test_12_national_id_foreign_is_skipped(self):
        # G13: a foreign driver has no Iranian national id and must not fail
        self.assertEqual(
            self.service.check_national_id("TR-99-XYZ", nationality="foreign"),
            "TR-99-XYZ",
        )
        self.assertEqual(self.service.check_national_id(False), "")

    # ----------------------------------------------------------------- mobile
    def test_20_mobile_positive(self):
        self.assertEqual(self.service.check_mobile("09123456789"), "09123456789")
        self.assertEqual(self.service.check_mobile("+98 912 345 6789"), "09123456789")
        self.assertEqual(
            self.service.check_mobile("\u06f0\u06f9\u06f1\u06f2\u06f3\u06f4\u06f5\u06f6\u06f7\u06f8\u06f9"),
            "09123456789",
        )

    def test_21_mobile_negative(self):
        for bad in ("08123456789", "0912345678", "091234567890", "hello"):
            with self.subTest(value=bad), self.assertRaises(ValidationError):
                self.service.check_mobile(bad)

    # ------------------------------------------------------------------ sheba
    def test_30_sheba_positive(self):
        self.assertEqual(
            self.service.check_sheba("IR93 0150-0000 0135 1800 0872 01"),
            "IR930150000001351800087201",
        )

    def test_31_sheba_negative(self):
        for bad in (
            "IR930150000001351800087202",
            "US930150000001351800087201",
            "IR000000000000000000000000",
            "IR9301500000013518000872",
        ):
            with self.subTest(value=bad), self.assertRaises(ValidationError):
                self.service.check_sheba(bad)

    def test_32_sheba_mask_policy(self):
        masked = self.service.mask_sheba("IR930150000001351800087201")
        self.assertEqual(masked, "IR93****7201")
        self.assertEqual(len(masked), 12)

    # ------------------------------------------------------------------ plate
    def test_40_plate_positive(self):
        canonical = self.service.check_plate("12 \u0628 345 \u0627\u06cc\u0631\u0627\u0646 67")
        self.assertTrue(canonical.startswith("12 "))
        self.assertTrue(canonical.endswith(" 67"))
        self.assertTrue(
            self.service.check_plate("\u06f1\u06f2\u0628\u06f3\u06f4\u06f5\u06f6\u06f7")
        )

    def test_41_plate_negative_and_transit(self):
        with self.assertRaises(ValidationError):
            self.service.check_plate("TR 34 ABC 12")
        # G13: transit plates keep their own format, no Iranian regex applies
        self.assertEqual(
            self.service.check_plate("TR 34 ABC 12", plate_type="transit"),
            "TR 34 ABC 12",
        )

    # ---------------------------------------------------------------- helpers
    def test_50_digit_helpers(self):
        self.assertEqual(self.service.to_latin_digits("\u06f0\u06f9\u06f1\u06f2"), "0912")
        self.assertEqual(self.service.to_persian_digits("0912"), "\u06f0\u06f9\u06f1\u06f2")

    def test_60_pure_layer_selftest(self):
        result = validators.self_test()
        self.assertTrue(result["ok"], "pure validators failed: %s" % result["failed"])
        self.assertGreaterEqual(result["checked"], 20)

    def test_70_service_is_the_only_entry_point(self):
        # the guarded layer must be reachable as a plain Odoo service model
        self.assertIn("itr.validation.service", self.env)
        self.assertTrue(self.env["itr.validation.service"].validators_selftest()["ok"])
PYEOF

write_utf8 "${MOD_DIR}/tests/test_jalali.py" <<'PYEOF'
# -*- coding: utf-8 -*-
import datetime

from odoo.tests import tagged

from .common import ItrBaseCase


@tagged("post_install", "-at_install", "itr_base")
class TestItrJalali(ItrBaseCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.operator = cls._itr_create_user("test_itr_calendar")
        cls.service = cls.env["itr.validation.service"].with_user(cls.operator)

    def test_10_roundtrip_on_boundary_dates(self):
        result = self.service.jalali_selftest()
        self.assertTrue(result["ok"], "jalali roundtrip failed: %s" % result["failed"])
        self.assertGreaterEqual(
            result["checked"], 50, "at least 50 boundary dates are required (1.3)"
        )
        self.assertGreaterEqual(result["anchors"], 10)

    def test_20_known_anchors(self):
        self.assertEqual(self.service.to_jalali(datetime.date(2025, 3, 20)), "1403/12/30")
        self.assertEqual(self.service.to_jalali(datetime.date(2025, 3, 21)), "1404/01/01")
        self.assertEqual(self.service.to_jalali(datetime.date(2026, 3, 21)), "1405/01/01")

    def test_30_display_formats(self):
        self.assertEqual(
            self.service.to_jalali(datetime.date(2025, 3, 21), persian_digits=True),
            "\u06f1\u06f4\u06f0\u06f4/\u06f0\u06f1/\u06f0\u06f1",
        )
        self.assertEqual(self.service.to_jalali(""), "")
        self.assertEqual(self.service.to_jalali(False), "")
        self.assertTrue(self.service.to_jalali_long(datetime.date(2025, 3, 21)))

    def test_40_parse_jalali_input(self):
        self.assertEqual(
            self.service.parse_jalali("1404/01/01"), datetime.date(2025, 3, 21)
        )
        self.assertEqual(
            self.service.parse_jalali("\u06f1\u06f4\u06f0\u06f3-\u06f1\u06f2-\u06f3\u06f0"),
            datetime.date(2025, 3, 20),
        )
        self.assertIsNone(self.service.parse_jalali("not-a-date"))
        # 1404 is not a leap year: 30 esfand does not exist
        self.assertIsNone(self.service.parse_jalali("1404/12/30"))

    def test_50_storage_stays_gregorian(self):
        """ADR-001: the ORM always stores gregorian, jalali is display only."""
        row = self.env["itr.validation.bypass.log"].with_user(self.operator).create({
            "check_kind": "national_id",
            "raw_value": "TEST calendar storage",
            "reason": "TEST ADR-001 storage proof",
            "acted_on": datetime.datetime(2025, 3, 21, 8, 30, 0),
        })
        self.assertIsInstance(row.acted_on, datetime.datetime)
        self.assertEqual(row.acted_on.year, 2025)
        self.assertEqual(row.acted_on.month, 3)
        self.assertEqual(row.acted_on.day, 21)
        self.assertEqual(self.service.to_jalali(row.acted_on), "1404/01/01")
        # a jalali string is never stored, it is produced on the fly
        self.assertEqual(
            self.service.parse_jalali(self.service.to_jalali(row.acted_on)),
            datetime.date(2025, 3, 21),
        )
PYEOF

write_utf8 "${MOD_DIR}/tests/test_settings_bypass.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged

from .common import ItrBaseCase


@tagged("post_install", "-at_install", "itr_base")
class TestItrSettingsAndBypassLog(ItrBaseCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.plain_user = cls._itr_create_user("test_itr_plain")
        cls.settings_manager = cls._itr_create_user(
            "test_itr_settings_mgr", ["itr_base.group_itr_settings_manager"]
        )
        cls.override_user = cls._itr_create_user(
            "test_itr_override",
            [
                "itr_base.group_itr_settings_manager",
                "itr_base.group_itr_validation_override",
            ],
        )

    # ---------------------------------------------------------------- positive
    def test_10_settings_singleton(self):
        settings = self.env["itr.common.settings"].with_user(self.plain_user).get_settings()
        self.assertTrue(settings)
        self.assertEqual(self.env["itr.common.settings"].search_count([]), 1)
        self.assertEqual(settings.default_country_code, "IR")

    def test_20_override_user_can_disable_with_reason(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        before = self.env["itr.validation.bypass.log"].with_user(self.override_user).search_count([])
        settings.write({
            "enable_national_id_check": False,
            "switch_change_reason": "TEST phase-1 verification",
        })
        logs = self.env["itr.validation.bypass.log"].with_user(self.override_user).search(
            [("check_kind", "=", "settings")], order="id desc", limit=1
        )
        self.assertEqual(
            self.env["itr.validation.bypass.log"].with_user(self.override_user).search_count([]),
            before + 1,
        )
        self.assertEqual(logs.acted_by_id, self.override_user)
        self.assertIn("TEST phase-1 verification", logs.reason)
        self.assertEqual(logs.raw_value, "national_id:1->0")

    def test_30_disabled_check_accepts_and_logs(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        settings.write({
            "enable_mobile_check": False,
            "switch_change_reason": "TEST bypass proof",
        })
        service = self.env["itr.validation.service"].with_user(self.plain_user)
        before = self.env["itr.validation.bypass.log"].sudo().search_count([])
        value = service.check_mobile("08123456789", res_model="res.partner", res_id=1)
        self.assertEqual(value, "08123456789")
        self.assertEqual(
            self.env["itr.validation.bypass.log"].sudo().search_count([]), before + 1
        )
        row = self.env["itr.validation.bypass.log"].sudo().search([], order="id desc", limit=1)
        self.assertEqual(row.check_kind, "mobile")
        self.assertEqual(row.acted_by_id, self.plain_user)
        self.assertTrue(row.reason)

    def test_40_sheba_is_masked_inside_the_audit_row(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        settings.write({
            "enable_sheba_check": False,
            "switch_change_reason": "TEST sheba masking",
        })
        service = self.env["itr.validation.service"].with_user(self.plain_user)
        service.check_sheba("IR930150000001351800087201")
        row = self.env["itr.validation.bypass.log"].sudo().search(
            [("check_kind", "=", "sheba")], order="id desc", limit=1
        )
        self.assertEqual(row.raw_value, "IR93****7201")
        self.assertNotIn("0150000001351800087201", row.raw_value or "")

    # ---------------------------------------------------------------- negative
    def test_50_plain_user_cannot_write_settings(self):
        settings = self.env["itr.common.settings"].with_user(self.plain_user).get_settings()
        with self.assertRaises(AccessError):
            settings.write({"note": "TEST should be refused"})

    def test_51_settings_manager_cannot_toggle_without_override(self):
        settings = self.env["itr.common.settings"].with_user(self.settings_manager).get_settings()
        with self.assertRaises(UserError):
            settings.write({
                "enable_plate_check": False,
                "switch_change_reason": "TEST refused",
            })

    def test_52_disable_without_reason_is_refused(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        with self.assertRaises(ValidationError):
            settings.write({"enable_plate_check": False})

    def test_60_bypass_log_cannot_be_deleted(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        settings.write({
            "enable_plate_check": False,
            "switch_change_reason": "TEST delete proof",
        })
        row = self.env["itr.validation.bypass.log"].with_user(self.override_user).search(
            [], order="id desc", limit=1
        )
        # the model level guard fires before the ACL, so UserError is expected
        # (AccessError is a subclass of UserError, both paths are covered)
        with self.assertRaises(UserError):
            row.unlink()
        # not even the superuser may delete an audit row
        with self.assertRaises(UserError):
            row.sudo().unlink()
        self.assertTrue(row.exists())

    def test_61_bypass_log_cannot_be_edited(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        settings.write({
            "enable_plate_check": False,
            "switch_change_reason": "TEST write proof",
        })
        row = self.env["itr.validation.bypass.log"].with_user(self.override_user).search(
            [], order="id desc", limit=1
        )
        with self.assertRaises(AccessError):
            row.write({"reason": "TEST tampering"})

    def test_62_plain_user_sees_only_his_own_rows(self):
        settings = self.env["itr.common.settings"].with_user(self.override_user).get_settings()
        settings.write({
            "enable_national_id_check": False,
            "switch_change_reason": "TEST record rule",
        })
        service = self.env["itr.validation.service"].with_user(self.plain_user)
        service.check_national_id("1234567890")
        visible = self.env["itr.validation.bypass.log"].with_user(self.plain_user).search([])
        self.assertTrue(visible)
        self.assertEqual(set(visible.mapped("acted_by_id")), {self.plain_user})

    def test_70_administrator_holds_no_itr_group(self):
        """Q03 / G01 negative test."""
        admin = self.env.ref("base.user_admin")
        self.assertFalse(admin.has_group("itr_base.group_itr_settings_manager"))
        self.assertFalse(admin.has_group("itr_base.group_itr_validation_override"))
PYEOF

# ---------------------------------------------------------------- README ----
write_utf8 "${MOD_DIR}/README.md" <<'MDEOF'
# itr_base — Iranian base infrastructure (Phase 1)

Dependency: `base` only. Install order (locked, Q02):

```
itr_base -> itr_notify -> itr_core -> itr_transport -> itr_reports -> itr_integration
```

## Public API for the next phases (never re-implement these)

```python
service = self.env['itr.validation.service']
service.check_national_id(value, nationality='ir', res_model=..., res_id=...)
service.check_mobile(value, res_model=..., res_id=...)
service.check_sheba(value, res_model=..., res_id=...)
service.check_plate(value, plate_type='ir', res_model=..., res_id=...)
service.mask_sheba(value)                # VAL-008, one policy everywhere
service.to_jalali(value, persian_digits=False)
service.to_jalali_long(value)
service.parse_jalali('1404/01/01')       # -> datetime.date (gregorian)
```

Pure layer (no Odoo import, unit testable):
`itr_base/utils/validators.py`, `itr_base/utils/jalali.py`.

## Hard rules enforced here
* ADR-001: storage gregorian/UTC, display jalali. Exactly ONE calendar engine.
* VAL-006/007: a switched-off check is never silent, needs the override group
  and a mandatory reason, and writes an undeletable audit row.
* NFR-007: a SHEBA is masked before it reaches any log.
* Q03: Administrator gets no ITR group.
MDEOF

log "درخت ماژول itr_base نوشته شد"

# =============================================================================
step "4) verify مستقل فاز ۱ (ops/verify/verify_phase1.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase1.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 1 independent verification (V1-01 .. V1-08).

Run through `odoo-bin shell` (read only, ADR-005). Every business assertion is
executed with a REAL non-admin user, never with sudo/Administrator (Q15/G01).
The whole run happens inside a single transaction which is ROLLED BACK at the
end, so the verification leaves zero footprint in the database.
"""
import traceback

from odoo.exceptions import AccessError, UserError, ValidationError

RESULTS = []


def check(code, title, func):
    try:
        detail = func()
        RESULTS.append((code, "PASS", title, detail or ""))
    except Exception as error:  # noqa: BLE001 - verification must never abort
        RESULTS.append((code, "FAIL", title, "%s: %s" % (type(error).__name__, error)))
        traceback.print_exc()


def create_user(env, login, group_xmlids):
    users = env["res.users"]
    group_field = "group_ids" if "group_ids" in users._fields else "groups_id"
    groups = env.ref("base.group_user")
    for xmlid in group_xmlids:
        groups |= env.ref(xmlid)
    existing = users.search([("login", "=", login)], limit=1)
    if existing:
        existing.write({group_field: [(6, 0, groups.ids)]})
        return existing
    return users.create({
        "name": "TEST %s" % login,
        "login": login,
        "email": "%s@test.invalid" % login,
        group_field: [(6, 0, groups.ids)],
    })


def main(env):
    plain = create_user(env, "test_itr_verify_plain", [])
    power = create_user(
        env,
        "test_itr_verify_override",
        [
            "itr_base.group_itr_settings_manager",
            "itr_base.group_itr_validation_override",
        ],
    )
    service = env["itr.validation.service"].with_user(plain)
    settings_plain = env["itr.common.settings"].with_user(plain).get_settings()
    settings_power = env["itr.common.settings"].with_user(power).get_settings()

    def v1_01():
        assert service.check_national_id("0084575948") == "0084575948"
        for bad in ("1234567890", "0013542418", "1111111111"):
            try:
                service.check_national_id(bad)
            except ValidationError:
                continue
            raise AssertionError("invalid national id accepted: %s" % bad)
        return "valid accepted / 3 invalid refused"

    def v1_02():
        assert service.check_mobile("+98 912 345 6789") == "09123456789"
        try:
            service.check_mobile("08123456789")
        except ValidationError:
            return "valid accepted / invalid refused"
        raise AssertionError("invalid mobile accepted")

    def v1_03():
        try:
            service.check_sheba("IR930150000001351800087202")
        except ValidationError:
            masked = service.mask_sheba("IR930150000001351800087201")
            assert masked == "IR93****7201", masked
            return "invalid refused, mask=%s" % masked
        raise AssertionError("invalid sheba accepted")

    def v1_04():
        # V1-04 / G13: foreign identity without Iranian national id must be
        # accepted by the guarded layer without raising. Creating res.partner
        # requires base.group_partner_manager (Contact Creation) in Odoo 19 and
        # is OUT OF SCOPE for itr_base — that ACL is granted in phase 3 (SEC-011).
        # Proof is against itr.validation.service only (the phase-1 contract).
        value = service.check_national_id("PASSPORT-X-8891", nationality="foreign")
        assert value == "PASSPORT-X-8891", value
        assert service.check_national_id(False) == ""
        transit = service.check_plate("TR 34 ABC 12", plate_type="transit")
        assert transit == "TR 34 ABC 12", transit
        return "foreign identity accepted without national id"

    def v1_05():
        before = env["itr.validation.bypass.log"].with_user(power).search_count([])
        settings_power.write({
            "enable_national_id_check": False,
            "switch_change_reason": "TEST verify V1-05",
        })
        service.check_national_id("1234567890", res_model="res.partner", res_id=1)
        rows = env["itr.validation.bypass.log"].with_user(power).search(
            [], order="id desc", limit=2
        )
        after = env["itr.validation.bypass.log"].with_user(power).search_count([])
        assert after == before + 2, "expected 2 audit rows, got %s" % (after - before)
        kinds = set(rows.mapped("check_kind"))
        assert kinds == {"settings", "national_id"}, kinds
        assert all(row.reason for row in rows), "a reason is mandatory"
        assert rows.filtered(lambda r: r.check_kind == "national_id").acted_by_id == plain
        settings_power.write({
            "enable_national_id_check": True,
            "switch_change_reason": "TEST verify V1-05 restore",
        })
        return "switch off -> audit rows with user and reason"

    def v1_06():
        result = service.jalali_selftest()
        assert result["ok"], result["failed"][:5]
        assert result["checked"] >= 50, result["checked"]
        assert service.to_jalali("2025-03-21") == "1404/01/01"
        assert str(service.parse_jalali("1403/12/30")) == "2025-03-20"
        return "%s boundary dates + %s anchors OK" % (result["checked"], result["anchors"])

    def v1_07():
        admin = env.ref("base.user_admin")
        assert not admin.has_group("itr_base.group_itr_settings_manager")
        assert not admin.has_group("itr_base.group_itr_validation_override")
        return "Administrator holds no ITR group (Q03)"

    def v1_08():
        try:
            settings_plain.write({"note": "TEST must be refused"})
        except AccessError:
            pass
        else:
            raise AssertionError("plain user could write the settings")
        row = env["itr.validation.bypass.log"].with_user(power).search([], limit=1)
        if row:
            try:
                row.sudo().unlink()
            except UserError:
                return "settings write refused / audit row not deletable"
            raise AssertionError("audit row was deleted")
        return "settings write refused (no audit row to test deletion)"

    check("V1-01", "national id: valid accepted, invalid refused", v1_01)
    check("V1-02", "mobile: valid accepted, invalid refused", v1_02)
    check("V1-03", "sheba: invalid refused and mask is correct", v1_03)
    check("V1-04", "foreign identity without national id is accepted", v1_04)
    check("V1-05", "switching a check off writes an audit row (user + reason)", v1_05)
    check("V1-06", "jalali roundtrip on boundary dates is exact", v1_06)
    check("V1-07", "negative: Administrator has no business group", v1_07)
    check("V1-08", "negative: plain user cannot write settings / delete audit", v1_08)


try:
    main(env)  # noqa: F821 - provided by odoo shell
except Exception:  # noqa: BLE001
    traceback.print_exc()
    RESULTS.append(("V1-XX", "FAIL", "verify script crashed", "see traceback"))

FAILED = [row for row in RESULTS if row[1] != "PASS"]
print("")
print("---------------- PHASE 1 VERIFY ----------------")
for code, status, title, detail in RESULTS:
    print("ITR_VERIFY %s %s | %s | %s" % (code, status, title, detail))
print("------------------------------------------------")
print(
    "ITR_VERIFY_RESULT: %s passed=%d failed=%d"
    % ("PASS" if not FAILED else "FAIL", len(RESULTS) - len(FAILED), len(FAILED))
)

# zero footprint: the verification never commits anything
env.cr.rollback()  # noqa: F821
PYEOF
log "ops/verify/verify_phase1.py نوشته شد"

# =============================================================================
step "5) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python3 - "$MOD_DIR" "$OPS_DIR" <<'PYEOF'
import ast, csv, io, os, sys
import xml.etree.ElementTree as ET

mod_dir, ops_dir = sys.argv[1], sys.argv[2]
errors = []
py_count = xml_count = 0

for root_dir in (mod_dir, os.path.join(ops_dir, "verify")):
    for base, _dirs, files in os.walk(root_dir):
        if "__pycache__" in base:
            continue
        for name in files:
            path = os.path.join(base, name)
            if name.endswith(".py"):
                py_count += 1
                try:
                    ast.parse(io.open(path, encoding="utf-8").read(), filename=path)
                except SyntaxError as exc:
                    errors.append("PY  %s: %s" % (path, exc))
            elif name.endswith(".xml"):
                xml_count += 1
                try:
                    ET.parse(path)
                except ET.ParseError as exc:
                    errors.append("XML %s: %s" % (path, exc))

acl = os.path.join(mod_dir, "security", "ir.model.access.csv")
with io.open(acl, encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))
if not rows:
    errors.append("CSV ir.model.access.csv is empty")
for row in rows:
    if not row.get("model_id:id") or not row.get("group_id:id"):
        errors.append("CSV incomplete row: %s" % row)

print("checked: %d python file(s), %d xml file(s), %d acl row(s)" % (py_count, xml_count, len(rows)))
if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
SYNTAX_RC=$?
set -e
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G1-02" "نحو پایتون/XML/CSV ماژول سالم است" "PASS" "pre-install static check"
else
  gate "G1-02" "نحو پایتون/XML/CSV ماژول سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب"
fi

# =============================================================================
step "6) نصب/ارتقای itr_base روی ${DB_NAME}"
# =============================================================================
MOD_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
if [[ "${MOD_STATE}" == "installed" ]]; then
  INSTALL_FLAG="-u"
  info "ماژول از قبل نصب است → ارتقا (-u)"
else
  INSTALL_FLAG="-i"
  info "نصب تازه (-i)"
fi

set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  "${INSTALL_FLAG}" "${MODULE}" --stop-after-init --log-level=info \
  >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e

INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
MOD_STATE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${MOD_STATE_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${MOD_STATE_AFTER}" == "installed" ]]; then
  gate "G1-03" "نصب/ارتقای itr_base بدون خطا (Gate 1)" "PASS" "state=installed rc=0"
else
  gate "G1-03" "نصب/ارتقای itr_base بدون خطا (Gate 1)" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${MOD_STATE_AFTER} → ${INSTALL_LOG}"
  tail -n 40 "${INSTALL_LOG}"
fi

# ساختار دیتابیس: جدول‌ها، گروه‌ها، ACL، Rule، رکورد تنظیمات
TBL_SETTINGS="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_common_settings')")"
TBL_LOG="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_validation_bypass_log')")"
SETTINGS_ROWS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_common_settings")"
GRP_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base' AND model='res.groups'")"
ACL_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base' AND model='ir.model.access'")"
RULE_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base' AND model='ir.rule'")"
echo "settings_table=${TBL_SETTINGS} log_table=${TBL_LOG} settings_rows=${SETTINGS_ROWS} groups=${GRP_COUNT} acl=${ACL_COUNT} rules=${RULE_COUNT}"
if [[ "${TBL_SETTINGS}" == "itr_common_settings" && "${TBL_LOG}" == "itr_validation_bypass_log" \
      && "${SETTINGS_ROWS}" == "1" && "${GRP_COUNT}" == "2" && "${RULE_COUNT}" == "2" && "${ACL_COUNT}" -ge 6 ]]; then
  gate "G1-04" "مدل‌ها/گروه‌ها/ACL/Record Rule و رکورد تک‌تنظیمات ساخته شدند" "PASS" \
       "settings_rows=1 groups=2 acl=${ACL_COUNT} rules=2"
else
  gate "G1-04" "مدل‌ها/گروه‌ها/ACL/Record Rule و رکورد تک‌تنظیمات ساخته شدند" "FAIL" \
       "settings=${SETTINGS_ROWS} groups=${GRP_COUNT} acl=${ACL_COUNT} rules=${RULE_COUNT}"
fi

# =============================================================================
step "7) تست‌های خودکار Odoo با کاربر غیر-ادمین (1.9)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G1-05" "تست‌های خودکار ماژول سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "${MODULE}" --test-enable --test-tags "/${MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): ' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" ]]; then
    gate "G1-05" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "PASS" "${TEST_TOTAL:-tests} rc=0"
  elif [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" ]]; then
    gate "G1-05" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "WARN" \
         "Odoo موفق گزارش داد اما ${TEST_FAILS} خط مشکوک در لاگ هست → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): ' "${TEST_LOG}" | head -n 10 || true
  else
    gate "G1-05" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "FAIL" \
         "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): ' "${TEST_LOG}" | head -n 15 || true
  fi
fi

# =============================================================================
step "8) verify مستقل V1-01..V1-08 (بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G1-06" "verify مستقل فاز ۱ سبز است (V1-01..V1-08)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase1.py" \
    >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G1-06" "verify مستقل فاز ۱ سبز است (V1-01..V1-08)" "PASS" "${VERIFY_LINE}"
  else
    gate "G1-06" "verify مستقل فاز ۱ سبز است (V1-01..V1-08)" "FAIL" \
         "${VERIFY_LINE:-خروجی verify یافت نشد} (rc=${VERIFY_RC}) → ${VERIFY_LOG}"
    tail -n 30 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "9) گاردهای معماری (Gate 1: تک‌موتور تقویم، بدون sudo، نام ASCII)"
# =============================================================================
CAL_HITS="$(grep -rIn --include='*.py' --include='*.js' -E '(^|[^A-Za-z0-9_])(_jalali_calendar|_jalali_to_jdn|_jdn_to_jalali|_gregorian_to_jdn|_jdn_to_gregorian|jal_cal|j2d|d2j|g2d|d2g)[[:space:]]*\(' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v '/itr_base/utils/jalali.py:' || true)"
LIB_HITS="$(grep -rIn --include='*.py' -E '^[[:space:]]*(import|from)[[:space:]]+(jdatetime|khayyam|persiantools|jalali_core|convertdate|jalali_date)' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
if [[ -z "${CAL_HITS}" && -z "${LIB_HITS}" ]]; then
  gate "G1-07" "فقط یک موتور تقویم جلالی در کل مخزن (G18/ADR-001)" "PASS" "itr_base/utils/jalali.py"
else
  gate "G1-07" "فقط یک موتور تقویم جلالی در کل مخزن (G18/ADR-001)" "FAIL" \
       "$(echo "${CAL_HITS}${LIB_HITS}" | head -n3 | tr '\n' ' ')"
fi

SUDO_HITS="$(grep -rn --include='*.py' '\.sudo(' "${MOD_DIR}/models" "${MOD_DIR}/utils" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G1-08" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/Q03)" "PASS" "models/ و utils/ تمیز"
else
  gate "G1-08" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/Q03)" "FAIL" "$(echo "${SUDO_HITS}" | head -n3 | tr '\n' ' ')"
fi

NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${MOD_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${MOD_DIR}" 2>/dev/null || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G1-09" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n"
else
  gate "G1-09" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" \
       "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

PO_MSGS="$(grep -c '^msgstr "' "${MOD_DIR}/i18n/fa_IR.po" || true)"
FA_LANG="$(q "${DB_NAME}" "SELECT code FROM res_lang WHERE code LIKE 'fa%' AND active IS TRUE LIMIT 1")"
FA_TRANS="$(q "${DB_NAME}" "SELECT field_description->>'${FA_LANG:-fa_IR}' FROM ir_model_fields WHERE model='itr.common.settings' AND name='enable_national_id_check'")"
if [[ -n "${FA_TRANS}" && "${FA_TRANS}" != "Validate Iranian national ID" ]]; then
  gate "G1-10" "ترجمهٔ فارسی ماژول بارگذاری شد (1.8)" "PASS" "lang=${FA_LANG} msgstr=${PO_MSGS} sample=${FA_TRANS}"
else
  gate "G1-10" "ترجمهٔ فارسی ماژول بارگذاری شد (1.8)" "WARN" \
       "lang=${FA_LANG:-?} — در صورت نیاز: odoo-bin -d ${DB_NAME} -u ${MODULE} --i18n-overwrite --load-language=fa_IR --stop-after-init"
fi

# =============================================================================
step "10) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_common_settings")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base'")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_validation_bypass_log")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${MODULE}" \
  --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_common_settings")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base'")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_validation_bypass_log")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G1-11" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "settings|xmlid|log = ${CNT_AFTER}"
else
  gate "G1-11" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "11) نصب روی پایگاه‌دادهٔ UAT (0.12 / محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G1-12" "itr_base روی محیط UAT نصب شد" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G1-12" "itr_base روی محیط UAT نصب شد" "WARN" "محیط UAT یافت نشد"
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
    gate "G1-12" "itr_base روی محیط UAT نصب شد" "PASS" "${DB_NAME_UAT} state=installed"
  else
    gate "G1-12" "itr_base روی محیط UAT نصب شد" "FAIL" "rc=${UAT_RC} state=${UAT_AFTER} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "12) تست منفی سطح دیتابیس: Administrator بدون گروه کسب‌وکاری (Q03)"
# =============================================================================
REL_EXISTS="$(q "${DB_NAME}" "SELECT to_regclass('public.res_groups_users_rel')")"
if [[ "${REL_EXISTS}" == "res_groups_users_rel" ]]; then
  ADMIN_ITR_GROUPS="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_base' WHERE u.login='admin'")"
  if [[ "${ADMIN_ITR_GROUPS}" == "0" ]]; then
    gate "G1-13" "Administrator هیچ گروه ITR ندارد (تست منفی Q03)" "PASS" "0 group"
  elif [[ -z "${ADMIN_ITR_GROUPS}" ]]; then
    gate "G1-13" "Administrator هیچ گروه ITR ندارد (تست منفی Q03)" "WARN" "کوئری راستی‌آزمایی نتیجه‌ای برنگرداند"
  else
    gate "G1-13" "Administrator هیچ گروه ITR ندارد (تست منفی Q03)" "FAIL" "${ADMIN_ITR_GROUPS} گروه به admin چسبیده است"
  fi
else
  gate "G1-13" "Administrator هیچ گروه ITR ندارد (تست منفی Q03)" "WARN" "جدول رابطهٔ گروه‌ها یافت نشد"
fi

# =============================================================================
step "13) اسناد حاکمیتی: ADR / REUSE MAP / تحویل فاز"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-005" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-005 — اجرای verify از طریق odoo shell (استثنای کنترل‌شدهٔ Q01)
تصمیم: Q01 ساخت «دادهٔ تولیدی» با shell را ممنوع می‌کند. اسکریپت
ops/verify/verify_phase1.py هیچ دادهٔ تولیدی نمی‌سازد: کاربر آزمایشی و
رکوردهای TEST را داخل یک تراکنش می‌سازد و در پایان env.cr.rollback() می‌زند،
بنابراین ردپای صفر دارد. فایل نسخه‌کنترل‌شده است و غیرتعاملی اجرا می‌شود.
همهٔ ادعاهای کسب‌وکاری با کاربر واقعی (نه sudo/Administrator) اثبات می‌شوند.

## ADR-006 — سازگاری با تغییرات Odoo 19 در لایهٔ گروه‌ها
واقعیت‌های Odoo 19 که در itr_base رعایت شده‌اند:
  * res.groups.category_id حذف شده → privilege_id (مدل جدید res.groups.privilege
    که خودش به ir.module.category وصل است).
  * res.users.groups_id → group_ids ؛ res.groups.users → user_ids.
  * ir.rule.groups بدون تغییر باقی مانده است.
  * <menuitem groups="..."> همچنان معتبر است (به group_ids ترجمه می‌شود).
  * تگ <tree> جای خود را به <list> داده است.
کد پایتون (تست و verify) نام فیلد گروه را در زمان اجرا تشخیص می‌دهد تا انتقال
آیندهٔ نسخه، تست‌ها را نشکند.

## ADR-007 — لایهٔ Guarded تنها نقطهٔ ورود اعتبارسنجی
همهٔ ماژول‌های بعدی فقط از env['itr.validation.service'] استفاده می‌کنند.
توابع خالص (utils/validators.py، utils/jalali.py) بدون هیچ import از Odoo
نوشته شده‌اند تا هم تست‌پذیر باشند و هم هرگز کپی دوم پیدا نکنند (G18).
MDEOF
log "ADR-005/006/007 به ARCHITECTURE_DECISIONS.md افزوده شد"
else
  warn "ADR-005 از قبل ثبت شده — بدون تغییر"
fi

write_utf8 "${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'
# نقشهٔ استفادهٔ مجدد (Q14)

| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۱ | `base` هستهٔ Odoo (res.users, res.groups, ir.rule, ir.model.access) | امنیت و ACL استاندارد Odoo کامل است؛ ساخت مدل کاربر/نقش موازی ممنوع (Q13) |
| ۱ | `res.groups.privilege` + `ir.module.category` هستهٔ Odoo 19 | دسته‌بندی گروه‌ها در Odoo 19 از همین مسیر انجام می‌شود |
| ۱ | فیلدهای استاندارد Datetime/Date برای ذخیرهٔ تاریخ | ذخیره همیشه میلادی/UTC؛ جلالی فقط نمایش (ADR-001) |

## آنچه فازهای بعد باید از فاز ۱ بازاستفاده کنند (ساخت دوباره = Gate قرمز)
* `env['itr.validation.service'].check_national_id/check_mobile/check_sheba/check_plate`
* `env['itr.validation.service'].mask_sheba` → تنها سیاست ماسک شبا (VAL-008)
* `env['itr.validation.service'].to_jalali/to_jalali_long/parse_jalali` → تنها موتور تقویم (G18)
* `itr.validation.bypass.log` → تنها دفتر عبور از اعتبارسنجی
* `itr.common.settings` → تنها محل کلیدهای فعال/غیرفعال سنجه‌ها

## آنچه فاز ۱ عمداً نساخت (خارج از دامنه)
* هیچ مدل کسب‌وکاری (پرونده، حمل، پرداخت، اعلان)
* هیچ رویداد/پیامک (وظیفهٔ فاز ۲ — itr_notify)
* هیچ نقش کسب‌وکاری از ۱۳ گروه فاز ۳
MDEOF
log "docs/REUSE_MAP.md نوشته شد"

# =============================================================================
step "14) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G1-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
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
    gate "G1-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G1-14" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "15) ثبت Git + تگ phase-1 (Q09)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-1: itr_base (validators, jalali engine, settings, bypass audit, guarded layer)"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-1 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-1 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G1-15" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-1}"
else
  gate "G1-15" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi

SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' | grep -v 'test_itr' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G1-16" "هیچ رمز/داده حساسی وارد Git نشد (Q12/NFR-004)" "PASS" "clean"
else
  gate "G1-16" "هیچ رمز/داده حساسی وارد Git نشد (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 1 — گزارش پذیرش فاز ۱"
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

write_utf8 "${DOC_DIR}/PHASE1-DELIVERY.md" <<MDEOF
# تحویل فاز ۱ — itr_base (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-1
- وضعیت Gate 1: **${GATE_STATUS}** (هشدار: ${WARNS})

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 1.1 | اسکلت ماژول itr_base با وابستگی فقط به base | Q02 |
| 1.2 | توابع خالص: ارقام، کد ملی، موبایل، شبا Mod-97، پلاک، ماسک شبا | VAL-001..005، VAL-008 |
| 1.3 | تقویم جلالی تک‌موتوره + تست رفت‌وبرگشت روی ≥۵۰ تاریخ مرزی | ADR-001، G18، NFR-009 |
| 1.4 | مدل تک‌رکوردی itr.common.settings با ۴ کلید سنجه | VAL-006 |
| 1.5 | مدل itr.validation.bypass.log بدون امکان حذف، دلیل اجباری | VAL-006/007 |
| 1.6 | گروه‌های group_itr_settings_manager و group_itr_validation_override | SEC-011، VAL-007 |
| 1.7 | لایهٔ Guarded (itr.validation.service) با پشتیبانی غیرایرانی | G13 |
| 1.8 | i18n/fa_IR.po (+ fa.po) — برچسب فارسی فقط از ترجمه | Q05، G19 |
| 1.9 | تست خودکار با کاربر غیر-ادمین + verify مستقل V1-01..V1-08 | Q04، Q15، G01 |

## ۲) Scope خارج از فاز (عمداً انجام نشد)
هیچ مدل/رویداد کسب‌وکاری، هیچ پیامک، هیچ نقش از ۱۳ گروه فاز ۳،
هیچ گزارش و هیچ اتصال بیرونی. این‌ها به‌ترتیب کار فازهای ۲ تا ۱۱ هستند.

## ۳) فایل‌های ایجاد/تغییرکرده
\`\`\`
${MODULE}/__init__.py, __manifest__.py, hooks.py, README.md
${MODULE}/utils/{validators.py, jalali.py}
${MODULE}/models/{itr_common_settings.py, itr_validation_bypass_log.py, itr_validation_service.py}
${MODULE}/security/{itr_base_groups.xml, ir.model.access.csv, itr_base_rules.xml}
${MODULE}/data/itr_common_settings_data.xml
${MODULE}/views/{itr_common_settings_views.xml, itr_validation_bypass_log_views.xml, itr_base_menus.xml}
${MODULE}/i18n/{fa_IR.po, fa.po}
${MODULE}/tests/{common.py, test_validators.py, test_jalali.py, test_settings_bypass.py}
ops/verify/verify_phase1.py
docs/{REUSE_MAP.md, PHASE1-DELIVERY.md}, ARCHITECTURE_DECISIONS.md (ADR-005/006/007)
\`\`\`

## ۴) ماتریس دسترسی تغییرکرده
| مدل | base.group_user | Settings Manager | Validation Override |
|---|---|---|---|
| itr.common.settings | read | read/write | read/write |
| itr.validation.bypass.log | read(خودش)/create | read(همه)/create | read(همه)/create |

حذف برای هیچ‌کس مجاز نیست (حتی superuser — override روی unlink).

## ۵) نتیجهٔ Gate
| ID | وضعیت | سنجه | توضیح |
|---|---|---|---|
${GATE_TABLE}

## ۶) لاگ‌ها
- نصب: ${INSTALL_LOG}
- تست: ${TEST_LOG}
- verify: ${VERIFY_LOG}
- idempotency: ${IDEMP_LOG}
- UAT: ${UAT_LOG}

## ۷) Rollback آزموده‌شده
\`\`\`bash
# بازگشت به وضعیت پیش از فاز ۱:
bash ops/restore.sh <آخرین dump> <آخرین filestore.tar.gz> ${DB_NAME}
# یا حذف ماژول:
python ~/odoo/odoo-bin -c ${CONF_FILE} -d ${DB_NAME} --stop-after-init \\
  --log-level=warn -u base   # سپس Uninstall از UI ماژول itr_base
\`\`\`
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-1: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

URL:            http://127.0.0.1:${HTTP_PORT}   (admin / as12)
DB (dev):       ${DB_NAME}        DB (uat): ${DB_NAME_UAT}
ماژول:          ${MODULE}  (state=${MOD_STATE_AFTER})
مسیر ماژول:     ${MOD_DIR}
verify:         ${OPS_DIR}/verify/verify_phase1.py
گزارش تحویل:    ${DOC_DIR}/PHASE1-DELIVERY.md
Git:            HEAD=${GIT_HEAD}  tag=phase-1

اجرای دستی دوبارهٔ تست‌ها:
  python ${ODOO_DIR}/odoo-bin -c ${CONF_FILE} -d ${DB_NAME} -u ${MODULE} \\
    --test-enable --test-tags /${MODULE} --stop-after-init

اجرای دستی دوبارهٔ verify:
  python ${ODOO_DIR}/odoo-bin shell -c ${CONF_FILE} -d ${DB_NAME} --stop-after-init \\
    < ${OPS_DIR}/verify/verify_phase1.py
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 1 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۲ (itr_notify).${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 1 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۲ آغاز نمی‌شود.${NC}\n"
  exit 1
fi
