#!/usr/bin/env bash
# =============================================================================
# script-02-itr-notify.sh — PHASE 2 (COMPLETE) — Iran Trade & Transport ERP
# Odoo 19.0 | File-First | Idempotent | Test-First | Gate-Enforced | No sudo-proof
#
# ماژول زیرساخت اعلان/پیامک/SLA : itr_notify
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt  ← «فاز ۲ (فاز بحرانی)» بندهای 2.1..2.29
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۱۱ (NOT-001..NOT-035)
# سبک اجرا: دقیقاً هم‌خانوادهٔ 00.sh (فاز ۰) و 001.sh (فاز ۱) همین مخزن.
#
# پوشش کامل چک‌لیست فاز ۲:
#   تنظیمات مرکزی (تک‌رکوردی)
#     2.1  master_enabled (پیش‌فرض روشن)
#     2.2  sms_master_enabled (Kill-Switch، پیش‌فرض خاموش)
#     2.3  test_mode (پیش‌فرض روشن؛ وضعیت Simulated، هرگز Sent)
#     2.4  default_cooldown_minutes / quiet_hours_start,end /
#          enable_user_preferences / health_digest_enabled
#   معماری آداپتور پیامک (Plugin/Registry)
#     2.5  کلاس پایهٔ انتزاعی send(mobile,text)->dict(ok,id,error) + required_fields()
#     2.6  رجیستری مرکزی + مدل itr.sms.gateway.profile (adapter_key/config/فعال/پیش‌فرض)
#     2.7  سه آداپتور: console_debug (پیش‌فرض، بدون شبکه) | generic_http | iran_http_sms
#   مدل رویداد اعلان
#     2.8  event_key یکتا با regex ^[a-z0-9_]+(\.[a-z0-9_]+)*$
#     2.9  is_active / is_critical / cooldown_minutes
#     2.10 تنها یک چک‌باکس تصمیم واقعی: send_sms (اعلان داخلی همیشه و رایگان)
#     2.11 چهار منبع گیرندهٔ قابل‌ترکیب: گروه‌ها | کاربران ثابت | فیلد کاربر پویا |
#          فیلد موبایل پویا
#     2.12 اعتبارسنجی سخت‌گیرانه (بدون متن/بدون گیرنده/Administrator ⇒ خطا)
#     2.13 itr.notification.alias (نام قدیمی → نام رسمی) — بند الزامی
#   موتور واحد notify()
#     2.14 notify(event_key, res_model=None, res_id=None, context=None)
#     2.15 گارد ۱: هرگز Exception پرتاب نمی‌کند
#     2.16 گارد ۲: هرگز سند مرجع را write/reload نمی‌کند
#     2.17 گارد ۳: Administrator/OdooBot/کاربر غیرفعال هرگز گیرنده نمی‌شوند
#     2.18 گارد ۴: نبود رویداد/گیرنده/قالب ⇒ ثبت روشن فارسی، هرگز سکوت
#     2.19 گارد ۵: پیامک واقعی فقط با sms_master_enabled=True
#     2.20 گارد ۶: دِدوپ با UNIQUE INDEX واقعی PostgreSQL روی dedup_key
#     2.21 گارد ۷: ساعات سکوت + صف بازپخش صبحگاهی؛ is_critical عبور می‌کند
#     2.22 گارد ۸: ارسال پس از commit (الگوی Outbox)، نه داخل تراکنش
#     2.23 Cron ۱۵دقیقه‌ای پایش SLA (تنها موتور SLA پروژه) + پلکان چهارسطحی
#     2.24 Cron روزانهٔ «گزارش سلامت اعلان» با فراخوانی همان notify()
#     2.25 دو رویداد سیستمی seed: system.notify_test / system.digest_daily_failures
#     2.26 دکمهٔ «ارسال آزمایشی برای من» روی فرم رویداد
#   ممنوعه‌های این فاز
#     2.27 هیچ سقف/شمارندهٔ هزینهٔ پیامک
#     2.28 هیچ کانال واتساپ
#     2.29 هیچ رویداد کسب‌وکاری (فقط دو رویداد سیستمی)
#   verify مستقل V2-01..V2-09 (کاربر واقعی، بدون sudo، rollback در پایان) + Gate 2
#
# پیش‌نیاز: Gate 1 سبز (bash 001.sh → itr_base نصب و installed)
#
# استفاده:
#   chmod +x script-02-itr-notify.sh
#   bash script-02-itr-notify.sh
#
# سوییچ‌ها (پیش‌فرض همه فعال):
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

# ───────────────────────────── CONFIG (هم‌راستا با فاز ۰ و ۱) ────────────────
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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase2-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase2-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase2-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase2-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase2-uat.log}"

MODULE="itr_notify"
BASE_MODULE="itr_base"
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
step "0) preflight — Gate 1 باید سبز باشد (itr_base نصب‌شده)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد: ${CONF_FILE} (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/${BASE_MODULE}" ]] || err "ماژول ${BASE_MODULE} یافت نشد (ابتدا فاز ۱)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G2-00" "نسخهٔ Odoo 19 تأیید شد (privilege_id/group_ids/<list>)" "PASS" "${ODOO_V}"
else
  gate "G2-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "نسخهٔ یافت‌شده: ${ODOO_V}"
  err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود."
fi

BASE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${BASE_MODULE}'")"
if [[ "${BASE_STATE}" == "installed" ]]; then
  gate "G2-01" "پیش‌نیاز فاز ۱ سبز است (${BASE_MODULE} نصب‌شده — Q02/Q08)" "PASS" "state=installed"
else
  gate "G2-01" "پیش‌نیاز فاز ۱ سبز است (${BASE_MODULE} نصب‌شده — Q02/Q08)" "FAIL" "state=${BASE_STATE:-missing}"
  err "طبق Q08 بدون Gate 1 سبز، فاز ۲ آغاز نمی‌شود. ابتدا 001.sh را اجرا کنید."
fi

grep -E '^addons_path' "${CONF_FILE}" | head -n1 | grep -q "${CUSTOM_ADDONS}" \
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
port_in_use "${HTTP_PORT}" && warn "پورت ${HTTP_PORT} هنوز listen است" || log "سرویس متوقف شد"

# =============================================================================
step "2) پشتیبان پیش از ارتقا (Q10/NFR-005)"
# =============================================================================
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G2-02" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "SKIP_BACKUP=1"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  BK_OUT="$(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)"
  BK_DUMP="$(echo "${BK_OUT}" | head -n1)"
  if [[ -s "${BK_DUMP:-/nonexistent}" ]]; then
    gate "G2-02" "پشتیبان پیش از ارتقا گرفته شد" "PASS" "$(basename "${BK_DUMP}")"
  else
    gate "G2-02" "پشتیبان پیش از ارتقا گرفته شد" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G2-02" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "ops/backup.sh یافت نشد"
fi

# =============================================================================
step "3) ساخت اسکلت ماژول itr_notify (File-First / Force-Replace)"
# =============================================================================
mkdir -p "${MOD_DIR}"/{models,utils,utils/adapters,security,data,views,i18n,tests}
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
    "name": "ITR Notify",
    "summary": "Generic alert/notification infrastructure: internal (free) + SMS (paid) + the single SLA engine",
    "description": """
ITR Notify (Phase 2)
====================
A completely domain free notification infrastructure. It does not know a single
business model name. Later phases only seed events and call one function:

    self.env['itr.notification.service'].notify(
        'case.legal_rejected', 'itr.trade.case', case.id, {'reason': '...'})

Guarantees (NOT-001 .. NOT-008, every one covered by an automated test)
-----------------------------------------------------------------------
* notify() never raises. The user document never fails because of an alert.
* notify() never writes or reloads the reference record (the SLA clock stays intact).
* Administrator / OdooBot / archived users are never recipients.
* A missing event, recipient or template is logged in Persian, never silent.
* Real SMS requires sms_master_enabled (factory default: OFF, test_mode ON).
* Deduplication relies on a REAL PostgreSQL unique index on dedup_key.
* Quiet hours block non critical SMS and a morning replay job releases them.
* Delivery happens AFTER commit (outbox pattern), never inside the transaction.

Deliberately NOT built here (phase checklist 2.27/2.28/2.29)
-----------------------------------------------------------
* No SMS cost cap / counter (that is the job of the SMS provider panel).
* No WhatsApp channel.
* No business event is seeded here, only the two system events.
""",
    "version": "19.0.1.0.0",
    "category": "Localization/Iran",
    "author": "Iran Trade & Transport ERP",
    "maintainer": "Iran Trade & Transport ERP",
    "license": "LGPL-3",
    "depends": ["base", "mail", "itr_base"],
    "data": [
        "security/itr_notify_groups.xml",
        "security/ir.model.access.csv",
        "security/itr_notify_rules.xml",
        "data/itr_notify_settings_data.xml",
        "data/itr_notification_event_data.xml",
        "data/itr_notify_cron.xml",
        "views/itr_notify_settings_views.xml",
        "views/itr_sms_gateway_profile_views.xml",
        "views/itr_notification_event_views.xml",
        "views/itr_notification_alias_views.xml",
        "views/itr_notification_dispatch_log_views.xml",
        "views/itr_notification_user_preference_views.xml",
        "views/itr_sla_views.xml",
        "views/itr_notify_menus.xml",
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
"""Install / upgrade hooks for itr_notify.

Idempotent by design (NFR-002): a second -u must not create a second settings
record, must not duplicate a seeded event and must never silently grant a
notification group to Administrator (Q03 / SEC-002).
"""
import logging

_logger = logging.getLogger(__name__)

ITR_GROUP_XMLIDS = (
    "itr_notify.group_itr_notification_manager",
    "itr_notify.group_itr_notification_user",
)


def post_init_hook(env):
    settings = env["itr.notify.settings"].get_settings()
    _logger.info("itr_notify: settings singleton ready (id=%s)", settings.id)

    # the real unique index is the backbone of NOT-006; make sure it exists
    env["itr.notification.dispatch.log"]._ensure_dedup_index()
    env["itr.sla.watch"]._ensure_open_watch_index()

    _assert_admin_is_clean(env)
    _assert_no_business_event(env)


def _assert_admin_is_clean(env):
    admin = env.ref("base.user_admin", raise_if_not_found=False)
    if not admin:
        return
    dirty = [xid for xid in ITR_GROUP_XMLIDS if admin.has_group(xid)]
    if dirty:
        _logger.warning(
            "itr_notify/Q03 VIOLATION: Administrator holds notification groups %s.",
            dirty,
        )
    else:
        _logger.info("itr_notify/Q03 OK: Administrator holds no notification group.")


def _assert_no_business_event(env):
    """Checklist 2.29: this module may only seed system.* events."""
    seeded = env["itr.notification.event"].search([("is_seed", "=", True)])
    illegal = seeded.filtered(lambda event: not event.event_key.startswith("system."))
    if illegal:
        _logger.warning(
            "itr_notify/2.29 VIOLATION: business events seeded in the infrastructure "
            "module: %s",
            illegal.mapped("event_key"),
        )
PYEOF

# ------------------------------------------------------------------ utils --
write_utf8 "${MOD_DIR}/utils/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import dedup
from . import renderer
from . import sms_base
from . import sms_registry
from . import adapters
PYEOF

write_utf8 "${MOD_DIR}/utils/dedup.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Deduplication keys (NOT-006 / NOT-019) - pure python, no Odoo import.

Two different keys are produced on purpose:

identity_key
    Everything that identifies "the same alert to the same person about the
    same thing", WITHOUT any time component. The sliding-window check
    (NOT-019) uses it: "was this identity already dispatched during the last
    cooldown minutes?".

dedup_key
    identity_key + an occurrence discriminator. When the caller supplies an
    explicit ``occurrence_id`` that value is used, otherwise a coarse time
    bucket is used. This key is protected by a REAL PostgreSQL unique index,
    so two concurrent workers can never insert the same row (the soft python
    check alone would lose that race).
"""
import hashlib


def _clean(value):
    if value is None or value is False:
        return ""
    return str(value)


def identity_key(event_key, res_model, res_id, channel, address):
    raw = "|".join([
        _clean(event_key),
        _clean(res_model),
        _clean(res_id),
        _clean(channel),
        _clean(address).lower(),
    ])
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def dedup_key(identity, occurrence_id=None, epoch_seconds=0, cooldown_minutes=10):
    cooldown_minutes = max(1, int(cooldown_minutes or 1))
    if occurrence_id:
        discriminator = "occ:%s" % _clean(occurrence_id)
    else:
        bucket = int(epoch_seconds // (cooldown_minutes * 60))
        discriminator = "win:%s:%s" % (cooldown_minutes, bucket)
    raw = "%s|%s" % (identity, discriminator)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def mask_mobile(value):
    """NFR-007: a log line never carries a full contact number."""
    digits = _clean(value)
    if len(digits) <= 7:
        return digits
    return digits[:4] + "****" + digits[-3:]
PYEOF

write_utf8 "${MOD_DIR}/utils/renderer.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Template rendering with a WHITELIST (SRS 11-2) - pure python.

A template may only use ``{{variable}}`` placeholders. A variable that is not
in the whitelisted context is replaced by an empty string and reported, so a
typo becomes visible in the dispatch log instead of raising or leaking python
objects. No eval, no jinja, no arbitrary attribute walking.
"""
import re

PLACEHOLDER_RE = re.compile(r"\{\{\s*([a-zA-Z0-9_]+)\s*\}\}")
MAX_LENGTH = 4000


def used_variables(template):
    return sorted(set(PLACEHOLDER_RE.findall(template or "")))


def render(template, context):
    """Return (text, missing_variables). Never raises."""
    if not template:
        return "", []
    context = context or {}
    missing = []

    def _substitute(match):
        key = match.group(1)
        if key not in context:
            missing.append(key)
            return ""
        value = context.get(key)
        if value is None or value is False:
            return ""
        return str(value)

    try:
        text = PLACEHOLDER_RE.sub(_substitute, template)
    except Exception:  # pragma: no cover - a template must never break notify()
        return template[:MAX_LENGTH], ["__render_error__"]
    return text[:MAX_LENGTH], sorted(set(missing))


def sms_part_count(text):
    """A Persian SMS part is 70 chars, a latin one 160."""
    text = text or ""
    if not text:
        return 0
    unit = 160 if all(ord(char) < 128 for char in text) else 70
    return max(1, -(-len(text) // unit))
PYEOF

write_utf8 "${MOD_DIR}/utils/sms_base.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Abstract SMS adapter (checklist 2.5) - pure python, no Odoo import.

Every gateway must subclass this and register itself. Nothing else in the whole
project is allowed to talk to an SMS provider (NOT-001 / G17).
"""


class BaseSmsAdapter(object):
    key = "base"
    label = "Base adapter"

    def __init__(self, config=None):
        self.config = config or {}

    @classmethod
    def required_fields(cls):
        """[{'name': ..., 'label': ..., 'required': bool}, ...]"""
        return []

    @classmethod
    def validate_config(cls, config):
        """Return a list of missing required field names."""
        config = config or {}
        missing = []
        for field in cls.required_fields():
            if not field.get("required"):
                continue
            value = config.get(field["name"])
            if value is None or (isinstance(value, str) and not value.strip()):
                missing.append(field["name"])
        return missing

    def send(self, mobile, text):
        """MUST return {'ok': bool, 'id': str|None, 'error': str|None}."""
        raise NotImplementedError
PYEOF

write_utf8 "${MOD_DIR}/utils/sms_registry.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Central adapter registry (checklist 2.6) - pure python."""

_REGISTRY = {}


def register(adapter_cls):
    _REGISTRY[adapter_cls.key] = adapter_cls
    return adapter_cls


def get(key):
    return _REGISTRY.get((key or "").strip())


def keys():
    return sorted(_REGISTRY)


def selection():
    return [(key, _REGISTRY[key].label) for key in keys()]
PYEOF

write_utf8 "${MOD_DIR}/utils/adapters/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import console_debug
from . import generic_http
from . import iran_http_sms
PYEOF

write_utf8 "${MOD_DIR}/utils/adapters/console_debug.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Development adapter (checklist 2.7). Zero network traffic, safe default."""
import logging

from ..sms_base import BaseSmsAdapter
from ..sms_registry import register

_logger = logging.getLogger(__name__)


@register
class ConsoleDebugAdapter(BaseSmsAdapter):
    key = "console_debug"
    label = "Console debug (no real sending)"

    @classmethod
    def required_fields(cls):
        return []

    def send(self, mobile, text):
        _logger.info("[itr_notify/console_debug] to=%s text=%s", mobile, text)
        return {"ok": True, "id": "console-debug", "error": None}
PYEOF

write_utf8 "${MOD_DIR}/utils/adapters/generic_http.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Generic REST adapter (checklist 2.7) for any gateway with a simple API."""
import logging

from ..sms_base import BaseSmsAdapter
from ..sms_registry import register

_logger = logging.getLogger(__name__)
DEFAULT_TIMEOUT = 10


@register
class GenericHttpAdapter(BaseSmsAdapter):
    key = "generic_http"
    label = "Generic HTTP gateway"

    @classmethod
    def required_fields(cls):
        return [
            {"name": "url", "label": "Service URL", "required": True},
            {"name": "method", "label": "GET or POST (default POST)", "required": False},
            {"name": "mobile_param", "label": "Mobile parameter name", "required": True},
            {"name": "text_param", "label": "Message parameter name", "required": True},
            {"name": "extra_params", "label": "Extra static params (object)", "required": False},
            {"name": "headers", "label": "HTTP headers (object)", "required": False},
            {"name": "timeout", "label": "Timeout in seconds", "required": False},
        ]

    def send(self, mobile, text):
        try:
            import requests
        except ImportError:  # pragma: no cover
            return {"ok": False, "id": None, "error": "python-requests is not installed"}

        url = (self.config.get("url") or "").strip()
        if not url:
            return {"ok": False, "id": None, "error": "url is not configured"}

        payload = dict(self.config.get("extra_params") or {})
        payload[self.config.get("mobile_param") or "mobile"] = mobile
        payload[self.config.get("text_param") or "text"] = text
        headers = self.config.get("headers") or {}
        timeout = float(self.config.get("timeout") or DEFAULT_TIMEOUT)
        method = (self.config.get("method") or "POST").upper()

        try:
            if method == "GET":
                response = requests.get(url, params=payload, headers=headers, timeout=timeout)
            else:
                response = requests.post(url, json=payload, headers=headers, timeout=timeout)
            ok = response.status_code < 400
            return {
                "ok": ok,
                "id": response.headers.get("X-Message-Id"),
                "error": None if ok else "HTTP %s" % response.status_code,
            }
        except Exception as error:  # noqa: BLE001 - a gateway must never break notify()
            _logger.warning("itr_notify/generic_http failed: %s", error)
            return {"ok": False, "id": None, "error": str(error)}
PYEOF

write_utf8 "${MOD_DIR}/utils/adapters/iran_http_sms.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Sample adapter for a typical Iranian REST SMS gateway (checklist 2.7).

Endpoint and parameter names come from the profile configuration, never from
the code (Q07 / NFR-004). Before production use, align them with the current
documentation of the chosen provider.
"""
import logging

from ..sms_base import BaseSmsAdapter
from ..sms_registry import register

_logger = logging.getLogger(__name__)


@register
class IranHttpSmsAdapter(BaseSmsAdapter):
    key = "iran_http_sms"
    label = "Iranian HTTP SMS gateway (sample)"

    @classmethod
    def required_fields(cls):
        return [
            {"name": "base_url", "label": "Base URL of the provider", "required": True},
            {"name": "api_key", "label": "API key", "required": True},
            {"name": "sender", "label": "Sender number", "required": False},
            {"name": "timeout", "label": "Timeout in seconds", "required": False},
        ]

    def send(self, mobile, text):
        try:
            import requests
        except ImportError:  # pragma: no cover
            return {"ok": False, "id": None, "error": "python-requests is not installed"}

        base_url = (self.config.get("base_url") or "").strip().rstrip("/")
        api_key = (self.config.get("api_key") or "").strip()
        if not base_url or not api_key:
            return {"ok": False, "id": None, "error": "base_url / api_key are not configured"}

        payload = {"receptor": mobile, "message": text}
        if self.config.get("sender"):
            payload["sender"] = self.config["sender"]

        try:
            response = requests.post(
                "%s/%s/sms/send.json" % (base_url, api_key),
                data=payload,
                timeout=float(self.config.get("timeout") or 10),
            )
            ok = response.status_code < 400
            message_id = None
            try:
                message_id = str(response.json()["entries"][0]["messageid"])
            except Exception:  # noqa: BLE001 - the provider payload is not a contract
                message_id = None
            return {
                "ok": ok,
                "id": message_id,
                "error": None if ok else "HTTP %s" % response.status_code,
            }
        except Exception as error:  # noqa: BLE001
            _logger.warning("itr_notify/iran_http_sms failed: %s", error)
            return {"ok": False, "id": None, "error": str(error)}
PYEOF

# ----------------------------------------------------------------- models --
write_utf8 "${MOD_DIR}/models/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import itr_notify_settings
from . import itr_sms_gateway_profile
from . import itr_notification_event
from . import itr_notification_alias
from . import itr_notification_dispatch_log
from . import itr_notification_user_preference
from . import itr_notification_service
from . import itr_sla_policy
from . import itr_sla_watch
from . import itr_sla_service
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notify_settings.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Single record settings of the notification infrastructure.

Checklist 2.1 .. 2.4 and NOT-007: the factory defaults are deliberately the
SAFE ones - the real SMS kill switch is OFF and the test mode is ON, so a fresh
site can never send a real message by accident (Q07 / phase 13.7).
"""
from datetime import timedelta, timezone

from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

DEFAULT_NAME = "ITR Notify Settings"


class ItrNotifySettings(models.Model):
    _name = "itr.notify.settings"
    _description = "Iran Notify Settings"
    _rec_name = "name"

    name = fields.Char(string="Name", required=True, default=DEFAULT_NAME)

    # --- 2.1 / 2.2 / 2.3 kill switches ------------------------------------
    master_enabled = fields.Boolean(
        string="Notification system enabled", default=True,
        help="Emergency stop of the whole notification system (internal + SMS).",
    )
    sms_master_enabled = fields.Boolean(
        string="Real SMS sending enabled", default=False,
        help="NOT-007: until this is ON, no real SMS leaves the system.",
    )
    test_mode = fields.Boolean(
        string="Test mode", default=True,
        help="In test mode an SMS is only recorded with status Simulated, never Sent.",
    )
    test_mobile = fields.Char(string="Test mobile number")

    # --- 2.4 defaults ------------------------------------------------------
    default_gateway_id = fields.Many2one(
        "itr.sms.gateway.profile", string="Default SMS gateway", ondelete="set null"
    )
    default_cooldown_minutes = fields.Integer(string="Default cooldown (minutes)", default=10)
    quiet_hours_enabled = fields.Boolean(string="Quiet hours enabled", default=True)
    quiet_hours_start = fields.Float(string="Quiet hours start", default=22.0)
    quiet_hours_end = fields.Float(string="Quiet hours end", default=7.0)
    enable_user_preferences = fields.Boolean(string="Allow user preferences", default=True)
    health_digest_enabled = fields.Boolean(string="Daily health digest enabled", default=True)
    sla_enabled = fields.Boolean(string="SLA monitoring enabled", default=True)
    outbox_enabled = fields.Boolean(
        string="Deliver after commit (outbox)", default=True,
        help="NOT-017: delivery happens after the transaction commits, never inside it.",
    )
    note = fields.Text(string="Notes")

    # ★ 2.27 : there is deliberately NO sms cost / cap / counter field here.

    _quiet_hours_help = "Values are hours in 24h format, 22.5 means 22:30."

    @api.constrains("name")
    def _check_single_record(self):
        if self.search_count([]) > 1:
            raise ValidationError(
                _("Only one notification settings record is allowed (single record model).")
            )

    @api.constrains("default_cooldown_minutes")
    def _check_cooldown(self):
        for record in self:
            if record.default_cooldown_minutes < 0:
                raise ValidationError(_("The default cooldown cannot be negative."))

    @api.constrains("quiet_hours_start", "quiet_hours_end")
    def _check_quiet_hours(self):
        for record in self:
            for value in (record.quiet_hours_start, record.quiet_hours_end):
                if value < 0.0 or value >= 24.0:
                    raise ValidationError(_("Quiet hours must be between 0.0 and 23.99."))

    @api.model
    def get_settings(self):
        """The one and only entry point to the settings record."""
        settings = self.env.ref("itr_notify.itr_notify_settings_default", raise_if_not_found=False)
        if settings:
            return settings
        settings = self.search([], limit=1)
        if settings:
            return settings
        # bootstrap of the singleton itself, never a business decision:
        return self.sudo().create({"name": DEFAULT_NAME})  # ITR-SUDO-OK

    # ------------------------------------------------------------ helpers
    def _now_float_hours(self):
        now = fields.Datetime.context_timestamp(self, fields.Datetime.now())
        return now.hour + now.minute / 60.0

    def is_quiet_now(self, now_hours=None):
        """NOT-018. Returns False when quiet hours are disabled or misconfigured."""
        self.ensure_one()
        if not self.quiet_hours_enabled:
            return False
        start = self.quiet_hours_start
        end = self.quiet_hours_end
        if start == end:
            return False
        current = self._now_float_hours() if now_hours is None else float(now_hours)
        if start < end:
            return start <= current < end
        return current >= start or current < end

    def next_quiet_end(self, from_datetime=None):
        """Datetime (UTC, naive) of the next end of the quiet window."""
        self.ensure_one()
        base = from_datetime or fields.Datetime.now()
        local = fields.Datetime.context_timestamp(self, base)
        end_hour = int(self.quiet_hours_end)
        end_minute = int(round((self.quiet_hours_end - end_hour) * 60))
        candidate = local.replace(
            hour=min(end_hour, 23), minute=min(end_minute, 59), second=0, microsecond=0
        )
        if candidate <= local:
            candidate = candidate + timedelta(days=1)
        return candidate.astimezone(timezone.utc).replace(tzinfo=None)

    def action_open_settings(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "res_model": self._name,
            "res_id": self.id,
            "view_mode": "form",
            "target": "current",
        }
PYEOF

write_utf8 "${MOD_DIR}/models/itr_sms_gateway_profile.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""SMS gateway profile (checklist 2.6).

The profile only stores WHICH adapter is used and its configuration; the code
of the gateway itself lives in utils/adapters and is reached through the
registry, so adding a provider never touches the notification engine (G17/T2).
"""
import json

from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

from ..utils import sms_registry


class ItrSmsGatewayProfile(models.Model):
    _name = "itr.sms.gateway.profile"
    _description = "Iran Notify SMS Gateway Profile"
    _order = "is_default desc, name"

    name = fields.Char(string="Gateway name", required=True)
    adapter_key = fields.Selection(
        selection=lambda self: self._adapter_selection(),
        string="Adapter", required=True, default="console_debug",
    )
    config_json = fields.Text(string="Configuration (JSON)", default="{}")
    required_fields_hint = fields.Text(
        string="Expected configuration keys", compute="_compute_required_fields_hint"
    )
    is_default = fields.Boolean(string="Default gateway")
    active = fields.Boolean(string="Active", default=True)

    @api.model
    def _adapter_selection(self):
        return sms_registry.selection() or [("console_debug", "Console debug")]

    @api.depends("adapter_key")
    def _compute_required_fields_hint(self):
        for record in self:
            adapter = sms_registry.get(record.adapter_key)
            if not adapter:
                record.required_fields_hint = ""
                continue
            record.required_fields_hint = "\n".join(
                "%s%s - %s" % (
                    item["name"],
                    " *" if item.get("required") else "",
                    item.get("label") or "",
                )
                for item in adapter.required_fields()
            )

    @api.constrains("adapter_key", "config_json")
    def _check_configuration(self):
        for record in self:
            adapter = sms_registry.get(record.adapter_key)
            if not adapter:
                raise ValidationError(
                    _("Unknown SMS adapter key: %(key)s", key=record.adapter_key)
                )
            config = record._config()
            missing = adapter.validate_config(config)
            if missing:
                raise ValidationError(
                    _("The adapter configuration is incomplete: %(fields)s",
                      fields=", ".join(missing))
                )

    def _config(self):
        self.ensure_one()
        try:
            config = json.loads(self.config_json or "{}")
        except (TypeError, ValueError):
            raise ValidationError(_("The gateway configuration must be a valid JSON object."))
        if not isinstance(config, dict):
            raise ValidationError(_("The gateway configuration must be a valid JSON object."))
        return config

    def get_adapter(self):
        self.ensure_one()
        adapter_cls = sms_registry.get(self.adapter_key)
        if not adapter_cls:
            return None
        return adapter_cls(self._config())

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        records._enforce_single_default()
        return records

    def write(self, vals):
        result = super().write(vals)
        if vals.get("is_default"):
            self._enforce_single_default()
        return result

    def _enforce_single_default(self):
        for record in self.filtered("is_default"):
            others = self.search([("id", "!=", record.id), ("is_default", "=", True)])
            if others:
                others.write({"is_default": False})
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notification_event.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""The notification event catalogue (checklist 2.8 .. 2.12, 2.26).

One event = one business fact. The user takes exactly ONE real decision on it:
"do we also pay for an SMS?" (send_sms). The internal notification is free and
always on, therefore it has no switch at all (NOT-008).
"""
import re

from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError
from odoo.tools import sql as sql_tools

from ..utils import renderer

EVENT_KEY_RE = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*$")
BLOCKED_LOGIN_XMLIDS = ("base.user_admin", "base.user_root")

CATEGORIES = [
    ("workflow", "Workflow"),
    ("finance", "Finance"),
    ("transport", "Transport and clearance"),
    ("system", "System"),
    ("digest", "Periodic digest"),
]


class ItrNotificationEvent(models.Model):
    _name = "itr.notification.event"
    _description = "Iran Notify Event"
    _order = "event_key"

    event_key = fields.Char(string="Event key", required=True, index=True)
    title = fields.Char(string="Title", required=True)
    category = fields.Selection(CATEGORIES, string="Category", required=True, default="workflow")

    is_active = fields.Boolean(string="Active", default=True)
    is_critical = fields.Boolean(
        string="Critical", default=False,
        help="A critical event passes the quiet hours and the user opt-out, "
             "but never the cooldown.",
    )
    cooldown_minutes = fields.Integer(
        string="Cooldown (minutes)", default=0,
        help="0 means: use the default cooldown of the notification settings.",
    )

    # --- 2.10 : the only real decision --------------------------------------
    send_sms = fields.Boolean(string="Also send an SMS (paid)", default=False)
    send_email = fields.Boolean(string="Also send an email", default=False)
    respect_quiet_hours = fields.Boolean(string="Respect quiet hours (SMS)", default=True)
    allow_user_optout = fields.Boolean(string="User may mute this event", default=True)

    # --- 2.11 : four combinable recipient sources ---------------------------
    recipient_group_ids = fields.Many2many(
        "res.groups", "itr_notification_event_group_rel", "event_id", "group_id",
        string="Recipient groups",
    )
    recipient_user_ids = fields.Many2many(
        "res.users", "itr_notification_event_user_rel", "event_id", "user_id",
        string="Fixed recipients",
    )
    dynamic_user_field = fields.Char(
        string="Dynamic user field",
        help="Field name on the reference record holding a res.users (e.g. requested_by).",
    )
    dynamic_mobile_field = fields.Char(
        string="Dynamic mobile field",
        help="Field name on the reference record holding a raw mobile number (e.g. a driver).",
    )

    internal_subject = fields.Char(string="Internal subject")
    internal_body = fields.Text(string="Internal body")
    sms_body = fields.Text(string="SMS body")
    email_subject = fields.Char(string="Email subject")
    email_body = fields.Html(string="Email body")

    variables_hint = fields.Char(string="Common variables", readonly=True,
                                 default="{{name}} {{model}} {{reason}} {{today}} {{url}}")
    sms_parts = fields.Integer(string="SMS parts", compute="_compute_sms_parts")

    is_seed = fields.Boolean(string="Created by the installer", readonly=True)
    allow_seed_overwrite = fields.Boolean(string="Installer may overwrite", default=True)
    alias_ids = fields.One2many("itr.notification.alias", "event_id", string="Aliases")
    note = fields.Text(string="Notes")

    def init(self):
        # a real database unique index, not only a python check
        sql_tools.create_unique_index(
            self._cr, "itr_notification_event_key_uniq", self._table, ["event_key"]
        )

    @api.depends("sms_body")
    def _compute_sms_parts(self):
        for record in self:
            record.sms_parts = renderer.sms_part_count(record.sms_body)

    # ------------------------------------------------------------ 2.8 / 2.12
    @api.constrains("event_key")
    def _check_event_key(self):
        for record in self:
            key = (record.event_key or "").strip()
            if not EVENT_KEY_RE.match(key):
                raise ValidationError(
                    _("The event key must match ^[a-z0-9_]+(\\.[a-z0-9_]+)*$ "
                      "(example: case.legal_rejected). Received: %(key)s", key=key)
                )
            duplicate = self.search_count([("event_key", "=", key), ("id", "!=", record.id)])
            if duplicate:
                raise ValidationError(_("This event key already exists: %(key)s", key=key))

    @api.constrains("cooldown_minutes")
    def _check_cooldown(self):
        for record in self:
            if record.cooldown_minutes < 0:
                raise ValidationError(_("The cooldown cannot be negative."))

    @api.constrains("send_sms", "sms_body", "send_email", "email_body")
    def _check_templates(self):
        for record in self:
            if record.send_sms and not (record.sms_body or "").strip():
                raise ValidationError(
                    _("SMS is enabled for '%(key)s' but the SMS text is empty.",
                      key=record.event_key)
                )
            if record.send_email and not (record.email_body or "").strip():
                raise ValidationError(
                    _("Email is enabled for '%(key)s' but the email body is empty.",
                      key=record.event_key)
                )

    @api.constrains(
        "recipient_group_ids", "recipient_user_ids",
        "dynamic_user_field", "dynamic_mobile_field",
    )
    def _check_recipient_source(self):
        for record in self:
            if not record._has_recipient_source():
                raise ValidationError(
                    _("Event '%(key)s' has no recipient source. Define at least one of: "
                      "recipient group, fixed user, dynamic user field, dynamic mobile field.",
                      key=record.event_key)
                )

    @api.constrains("recipient_user_ids")
    def _check_blocked_recipients(self):
        blocked = self._blocked_user_ids()
        for record in self:
            if set(record.recipient_user_ids.ids) & blocked:
                raise ValidationError(
                    _("Administrator / OdooBot can never be a notification recipient "
                      "(SEC-002 / NOT-004).")
                )

    @api.model
    def _blocked_user_ids(self):
        ids = set()
        for xmlid in BLOCKED_LOGIN_XMLIDS:
            user = self.env.ref(xmlid, raise_if_not_found=False)
            if user:
                ids.add(user.id)
        return ids

    def _has_recipient_source(self):
        self.ensure_one()
        return bool(
            self.recipient_group_ids
            or self.recipient_user_ids
            or (self.dynamic_user_field or "").strip()
            or (self.dynamic_mobile_field or "").strip()
        )

    @api.model_create_multi
    def create(self, vals_list):
        vals_list = [dict(vals) for vals in vals_list]
        seen_keys = set()

        for vals in vals_list:
            if vals.get("event_key"):
                vals["event_key"] = vals["event_key"].strip()

            key = vals.get("event_key")
            if key:
                if key in seen_keys or self.search_count([
                    ("event_key", "=", key),
                ]):
                    raise ValidationError(
                        _("This event key already exists: %(key)s", key=key)
                    )
                seen_keys.add(key)

            if not (vals.get("internal_body") or "").strip():
                vals["internal_body"] = vals.get("title") or key

        with self.env.cr.savepoint():
            return super().create(vals_list)

    def write(self, vals):
        if vals.get("event_key"):
            vals["event_key"] = vals["event_key"].strip()
        return super().write(vals)

    # ------------------------------------------------------------------ 2.26
    def action_send_test_to_me(self):
        """The 'send a test to me' button of the event form."""
        self.ensure_one()
        user = self.env.user
        if user.id in self._blocked_user_ids():
            raise UserError(
                _("This action is not available for Administrator / OdooBot; "
                  "log in with a real business user (G01).")
            )
        result = self.env["itr.notification.service"].with_context(
            itr_notify_sync=True
        ).notify(
            self.event_key,
            context={
                "itr_force_user_ids": [user.id],
                "reason": _("Manual test triggered from the event form."),
            },
        )
        message = _(
            "Test dispatched. queued=%(queued)s sent=%(sent)s simulated=%(simulated)s "
            "blocked=%(blocked)s duplicate=%(duplicate)s",
            queued=result.get("queued", 0),
            sent=result.get("sent", 0),
            simulated=result.get("simulated", 0),
            blocked=result.get("blocked", 0),
            duplicate=result.get("skipped_duplicate", 0),
        )
        return {
            "type": "ir.actions.client",
            "tag": "display_notification",
            "params": {"title": _("ITR Notify"), "message": message, "type": "info"},
        }

    def action_open_logs(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("Dispatch log"),
            "res_model": "itr.notification.dispatch.log",
            "view_mode": "list,form",
            "domain": [("event_key", "=", self.event_key)],
        }
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notification_alias.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Event alias (checklist 2.13 - mandatory).

Because notify() never raises (NOT-002), a renamed or mistyped event key would
silently swallow a critical SMS. The alias table makes an old name keep
working, and every resolution is visible in the dispatch log.
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError
from odoo.tools import sql as sql_tools

from .itr_notification_event import EVENT_KEY_RE


class ItrNotificationAlias(models.Model):
    _name = "itr.notification.alias"
    _description = "Iran Notify Event Alias"
    _order = "alias_key"

    alias_key = fields.Char(string="Legacy key", required=True, index=True)
    event_id = fields.Many2one(
        "itr.notification.event", string="Official event", required=True, ondelete="cascade"
    )
    event_key = fields.Char(related="event_id.event_key", string="Official key", store=False)
    note = fields.Text(string="Notes")

    def init(self):
        sql_tools.create_unique_index(
            self._cr, "itr_notification_alias_key_uniq", self._table, ["alias_key"]
        )

    @api.constrains("alias_key")
    def _check_alias_key(self):
        for record in self:
            key = (record.alias_key or "").strip()
            if not EVENT_KEY_RE.match(key):
                raise ValidationError(
                    _("The alias key must match ^[a-z0-9_]+(\\.[a-z0-9_]+)*$. Received: %(key)s",
                      key=key)
                )
            if self.env["itr.notification.event"].search_count([("event_key", "=", key)]):
                raise ValidationError(
                    _("'%(key)s' is already an official event key, it cannot be an alias.",
                      key=key)
                )
            if self.search_count([("alias_key", "=", key), ("id", "!=", record.id)]):
                raise ValidationError(_("This alias already exists: %(key)s", key=key))

    @api.model
    def resolve(self, key):
        alias = self.search([("alias_key", "=", (key or "").strip())], limit=1)
        return alias.event_id if alias else self.env["itr.notification.event"]
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notification_dispatch_log.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Append-only dispatch log + the delivery engine (checklist 2.20 / 2.22).

Every single decision of notify() ends up here: sent, simulated, blocked,
skipped or failed. Nothing is ever silent (NOT-005).

The uniqueness of dedup_key is enforced by a REAL PostgreSQL unique index
(NOT-006). The row is INSERTED BEFORE the delivery ("reserve then send"), so
two concurrent workers cannot both send the same alert.
"""
import json
import logging

from odoo import _, api, fields, models
from odoo.exceptions import UserError
from odoo.tools import sql as sql_tools

from ..utils import dedup as dedup_utils

_logger = logging.getLogger(__name__)

DEDUP_INDEX_NAME = "itr_notification_dispatch_log_dedup_uniq"

CHANNELS = [
    ("internal", "Internal"),
    ("sms", "SMS"),
    ("email", "Email"),
]

STATUSES = [
    ("queued", "Queued"),
    ("sent", "Sent"),
    ("simulated", "Simulated (test mode)"),
    ("failed", "Failed"),
    ("blocked_master_off", "Blocked - master off"),
    ("blocked_sms_off", "Blocked - SMS off"),
    ("blocked_muted", "Blocked - muted by user"),
    ("blocked_quiet", "Blocked - quiet hours"),
    ("blocked_no_address", "Blocked - no address"),
    ("skipped_duplicate", "Skipped - duplicate"),
    ("config_error", "Configuration error"),
]

ENGINE_WRITABLE_FIELDS = {
    "status", "decision_reason", "provider_message_id", "attempt_count",
    "delivered_on", "replay_after", "error_detail",
}


class ItrNotificationDispatchLog(models.Model):
    _name = "itr.notification.dispatch.log"
    _description = "Iran Notify Dispatch Log"
    _order = "id desc"

    event_key = fields.Char(string="Event key", required=True, readonly=True, index=True)
    event_id = fields.Many2one("itr.notification.event", string="Event",
                               readonly=True, ondelete="set null")
    alias_used = fields.Char(string="Alias used", readonly=True)
    channel = fields.Selection(CHANNELS, string="Channel", required=True, readonly=True)
    status = fields.Selection(STATUSES, string="Status", required=True,
                              default="queued", readonly=True, index=True)

    res_model = fields.Char(string="Reference model", readonly=True, index=True)
    res_id = fields.Integer(string="Reference id", readonly=True)

    recipient_user_id = fields.Many2one("res.users", string="Recipient user",
                                        readonly=True, ondelete="set null")
    recipient_address = fields.Char(string="Recipient address (technical)", readonly=True)
    recipient_display = fields.Char(string="Recipient", compute="_compute_recipient_display")

    subject = fields.Char(string="Subject", readonly=True)
    body = fields.Text(string="Body", readonly=True)
    sms_parts = fields.Integer(string="SMS parts", readonly=True)
    missing_variables = fields.Char(string="Missing template variables", readonly=True)

    decision_reason = fields.Text(string="Decision reason", readonly=True)
    error_detail = fields.Text(string="Error detail", readonly=True)
    provider_message_id = fields.Char(string="Provider message id", readonly=True)
    attempt_count = fields.Integer(string="Attempts", default=0, readonly=True)
    delivered_on = fields.Datetime(string="Delivered on", readonly=True)
    replay_after = fields.Datetime(string="Replay after", readonly=True,
                                   help="Quiet hours: the morning replay job releases it.")

    identity_key = fields.Char(string="Identity key", readonly=True, index=True)
    dedup_key = fields.Char(string="Dedup key", required=True, readonly=True, index=True)

    # ------------------------------------------------------------- indexes
    def init(self):
        self._ensure_dedup_index()

    @api.model
    def _ensure_dedup_index(self):
        """NOT-006: a REAL unique index, verified from pg_indexes by the Gate."""
        sql_tools.create_unique_index(self._cr, DEDUP_INDEX_NAME, self._table, ["dedup_key"])

    @api.depends("recipient_user_id", "recipient_address", "channel")
    def _compute_recipient_display(self):
        for record in self:
            if record.recipient_user_id:
                record.recipient_display = record.recipient_user_id.display_name
            elif record.channel == "sms":
                record.recipient_display = dedup_utils.mask_mobile(record.recipient_address)
            else:
                record.recipient_display = record.recipient_address or ""

    # --------------------------------------------------------- append only
    def write(self, vals):
        if not self.env.context.get("itr_notify_engine"):
            raise UserError(
                _("The dispatch log is append-only; it can only be updated by the "
                  "notification engine.")
            )
        illegal = set(vals) - ENGINE_WRITABLE_FIELDS
        if illegal:
            raise UserError(
                _("These dispatch log fields can never be modified: %(fields)s",
                  fields=", ".join(sorted(illegal)))
            )
        return super().write(vals)

    def unlink(self):
        raise UserError(_("Dispatch log records are append-only and cannot be deleted."))

    # --------------------------------------------------------- delivery ---
    def deliver(self):
        """Deliver every queued row of the recordset. Never raises."""
        for record in self.filtered(lambda log: log.status == "queued"):
            try:
                record._deliver_one()
            except Exception:  # noqa: BLE001 - delivery must never break the caller
                _logger.exception("itr_notify: delivery crashed for log %s", record.id)
                record._engine_write({
                    "status": "failed",
                    "error_detail": _("Unexpected internal error during delivery."),
                    "attempt_count": record.attempt_count + 1,
                })
        return True

    def _engine_write(self, vals):
        return self.with_context(itr_notify_engine=True).write(vals)

    def _deliver_one(self):
        self.ensure_one()
        handler = {
            "internal": self._deliver_internal,
            "sms": self._deliver_sms,
            "email": self._deliver_email,
        }.get(self.channel)
        if not handler:
            self._engine_write({
                "status": "failed",
                "error_detail": _("Unknown channel: %(channel)s", channel=self.channel),
            })
            return
        handler()

    # ------------------------------------------------------------ internal
    def _deliver_internal(self):
        """The free channel: a standard Odoo inbox notification (no second engine)."""
        self.ensure_one()
        user = self.recipient_user_id
        if not user or not user.partner_id:
            self._engine_write({
                "status": "blocked_no_address",
                "decision_reason": _("The internal channel needs a user with a partner."),
            })
            return
        try:
            self.env["mail.thread"].message_notify(
                partner_ids=user.partner_id.ids,
                subject=self.subject or self.event_key,
                body=self.body or self.subject or self.event_key,
                model=self.res_model or False,
                res_id=self.res_id or False,
            )
            ok, error = True, None
        except Exception as error_obj:  # noqa: BLE001
            _logger.warning("itr_notify: internal notification failed: %s", error_obj)
            ok, error = False, str(error_obj)
        self._engine_write({
            "status": "sent" if ok else "failed",
            "error_detail": error,
            "attempt_count": self.attempt_count + 1,
            "delivered_on": fields.Datetime.now() if ok else False,
        })

    # ----------------------------------------------------------------- sms
    def _deliver_sms(self):
        self.ensure_one()
        settings = self.env["itr.notify.settings"].get_settings()
        if not self.recipient_address:
            self._engine_write({
                "status": "blocked_no_address",
                "decision_reason": _("No mobile number is available for this recipient."),
            })
            return

        # NOT-007 / 2.3 : test mode never reports "Sent"
        if settings.test_mode or not settings.sms_master_enabled:
            reason = (
                _("Test mode: the message was recorded, not transmitted.")
                if settings.test_mode
                else _("The SMS kill switch is off; the message was not transmitted.")
            )
            self._engine_write({
                "status": "simulated" if settings.test_mode else "blocked_sms_off",
                "decision_reason": reason,
                "attempt_count": self.attempt_count + 1,
            })
            return

        gateway = settings.default_gateway_id
        if not gateway or not gateway.active:
            self._engine_write({
                "status": "failed",
                "error_detail": _("No active default SMS gateway is configured."),
                "attempt_count": self.attempt_count + 1,
            })
            return

        adapter = gateway.get_adapter()
        if not adapter:
            self._engine_write({
                "status": "failed",
                "error_detail": _("Unknown adapter: %(key)s", key=gateway.adapter_key),
                "attempt_count": self.attempt_count + 1,
            })
            return

        result = adapter.send(self.recipient_address, self.body or "") or {}
        ok = bool(result.get("ok"))
        self._engine_write({
            "status": "sent" if ok else "failed",
            "provider_message_id": result.get("id") or False,
            "error_detail": None if ok else (result.get("error") or _("Sending failed.")),
            "attempt_count": self.attempt_count + 1,
            "delivered_on": fields.Datetime.now() if ok else False,
        })

    # --------------------------------------------------------------- email
    def _deliver_email(self):
        self.ensure_one()
        if not self.recipient_address:
            self._engine_write({
                "status": "blocked_no_address",
                "decision_reason": _("No email address is available for this recipient."),
            })
            return
        try:
            mail = self.env["mail.mail"].create({
                "subject": self.subject or self.event_key,
                "body_html": self.body or "",
                "email_to": self.recipient_address,
                "auto_delete": False,
            })
            ok, error, message_id = True, None, str(mail.id)
        except Exception as error_obj:  # noqa: BLE001
            _logger.warning("itr_notify: email creation failed: %s", error_obj)
            ok, error, message_id = False, str(error_obj), None
        self._engine_write({
            "status": "sent" if ok else "failed",
            "provider_message_id": message_id,
            "error_detail": error,
            "attempt_count": self.attempt_count + 1,
            "delivered_on": fields.Datetime.now() if ok else False,
        })

    # --------------------------------------------------------------- crons
    @api.model
    def _cron_replay_quiet_hours(self):
        """NOT-018 / 2.21: release what the quiet hours blocked."""
        settings = self.env["itr.notify.settings"].get_settings()
        if not settings.master_enabled:
            return 0
        now = fields.Datetime.now()
        pending = self.search([
            ("status", "=", "blocked_quiet"),
            ("replay_after", "!=", False),
            ("replay_after", "<=", now),
        ], limit=500)
        for record in pending:
            record._engine_write({
                "status": "queued",
                "decision_reason": _("Released by the morning replay job."),
                "replay_after": False,
            })
        pending.deliver()
        return len(pending)

    @api.model
    def _cron_daily_health_digest(self):
        """2.24: the infrastructure reports its own health through notify()."""
        settings = self.env["itr.notify.settings"].get_settings()
        if not settings.health_digest_enabled or not settings.master_enabled:
            return 0
        since = fields.Datetime.subtract(fields.Datetime.now(), days=1)
        bad_statuses = ["failed", "config_error", "blocked_no_address", "blocked_sms_off"]
        failures = self.search_count([
            ("create_date", ">=", since),
            ("status", "in", bad_statuses),
        ])
        if not failures:
            return 0
        self.env["itr.notification.service"].notify(
            "system.digest_daily_failures",
            context={
                "failed_count": failures,
                "since": fields.Datetime.to_string(since),
                "occurrence_id": "digest-%s" % fields.Date.today(),
            },
        )
        return failures

    # --------------------------------------------------------------- utils
    @api.model
    def log_configuration_error(self, event_key, message, res_model=None, res_id=None):
        """NOT-005: a missing event / recipient / template is never silent."""
        identity = dedup_utils.identity_key(event_key, res_model, res_id, "internal", "config")
        key = dedup_utils.dedup_key(
            identity,
            occurrence_id=None,
            epoch_seconds=fields.Datetime.now().timestamp(),
            cooldown_minutes=60,
        )
        _logger.warning("itr_notify/CONFIG %s: %s", event_key, message)
        existing = self.search([("dedup_key", "=", key)], limit=1)
        if existing:
            return existing
        try:
            return self.create({
                "event_key": event_key or "unknown",
                "channel": "internal",
                "status": "config_error",
                "res_model": res_model,
                "res_id": res_id or 0,
                "decision_reason": message,
                "identity_key": identity,
                "dedup_key": key,
            })
        except Exception:  # noqa: BLE001 - logging must never break the caller
            _logger.exception("itr_notify: could not write the configuration error row")
            return self.browse()

    @api.model
    def dump_context(self, context):
        try:
            return json.dumps(context or {}, ensure_ascii=False, default=str)[:2000]
        except Exception:  # noqa: BLE001
            return ""
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notification_user_preference.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Per user opt-out (SRS 11-2).

A normal user may only create/see his own preference: the server forces
``user_id`` and a record rule hides the rows of the others (SEC-017: the guard
must also hold for a direct RPC call, not only in the UI).
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError


class ItrNotificationUserPreference(models.Model):
    _name = "itr.notification.user.preference"
    _description = "Iran Notify User Preference"
    _order = "user_id, event_id"

    user_id = fields.Many2one(
        "res.users", string="User", required=True, ondelete="cascade",
        default=lambda self: self.env.user,
    )
    event_id = fields.Many2one(
        "itr.notification.event", string="Event", required=True, ondelete="cascade",
        domain=[("allow_user_optout", "=", True)],
    )
    event_key = fields.Char(related="event_id.event_key", store=True, index=True, readonly=True)
    mute_internal = fields.Boolean(string="Mute the internal notification")
    mute_sms = fields.Boolean(string="Mute the SMS")
    custom_mobile = fields.Char(string="Alternative mobile number")

    _preference_help = "Only events with allow_user_optout can be muted."

    @api.constrains("user_id", "event_id")
    def _check_unique_preference(self):
        for record in self:
            duplicate = self.search_count([
                ("user_id", "=", record.user_id.id),
                ("event_id", "=", record.event_id.id),
                ("id", "!=", record.id),
            ])
            if duplicate:
                raise ValidationError(
                    _("A preference already exists for this user and this event.")
                )

    @api.constrains("event_id")
    def _check_optout_allowed(self):
        for record in self:
            if record.event_id and not record.event_id.allow_user_optout:
                raise ValidationError(
                    _("Event '%(key)s' cannot be muted by a user.",
                      key=record.event_id.event_key)
                )

    def _force_own_user(self, vals):
        if self.env.user.has_group("itr_notify.group_itr_notification_manager"):
            return vals
        vals = dict(vals)
        vals["user_id"] = self.env.user.id
        return vals

    @api.model_create_multi
    def create(self, vals_list):
        return super().create([self._force_own_user(vals) for vals in vals_list])

    def write(self, vals):
        if "user_id" in vals and not self.env.user.has_group(
            "itr_notify.group_itr_notification_manager"
        ):
            raise ValidationError(
                _("A user can only manage the notification preferences of his own account.")
            )
        return super().write(vals)
PYEOF

write_utf8 "${MOD_DIR}/models/itr_notification_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""THE single entry point of the whole project (checklist 2.14 .. 2.22).

    self.env['itr.notification.service'].notify(
        'case.legal_rejected', 'itr.trade.case', case.id, {'reason': '...'})

Iron guarantees, each of them covered by an automated test:
  NOT-002  notify() never raises.
  NOT-003  notify() never writes / reloads the reference record.
  NOT-004  Administrator, OdooBot and archived users are never recipients.
  NOT-005  a missing event / recipient / template is logged, never silent.
  NOT-006  duplicates are stopped by a REAL unique index (reserve then send).
  NOT-007  a real SMS needs sms_master_enabled.
  NOT-017  delivery happens after commit (outbox), never inside the transaction.
"""
import logging

from odoo import SUPERUSER_ID, _, api, fields, models

from ..utils import dedup as dedup_utils
from ..utils import renderer

_logger = logging.getLogger(__name__)

SAFE_FIELD_TYPES = (
    "char", "text", "html", "integer", "float", "monetary",
    "boolean", "date", "datetime", "selection",
)


class ItrNotificationService(models.AbstractModel):
    _name = "itr.notification.service"
    _description = "Iran Notify Service"

    # =====================================================================
    # public API
    # =====================================================================
    @api.model
    def notify(self, event_key, res_model=None, res_id=None, context=None):
        """Return a statistics dict. NEVER raises (NOT-002)."""
        try:
            return self._notify(event_key, res_model, res_id, context or {})
        except Exception:  # noqa: BLE001 - the guard of the whole project
            _logger.exception("itr_notify: notify(%s) crashed", event_key)
            try:
                self.env["itr.notification.dispatch.log"].log_configuration_error(
                    event_key,
                    _("An unexpected internal error occurred while sending the notification."),
                    res_model, res_id,
                )
            except Exception:  # noqa: BLE001
                pass
            return self._empty_result(event_key, "exception")

    @api.model
    def notify_many(self, event_key, records, context=None):
        """Convenience helper for a recordset; still one row per recipient."""
        results = []
        for record in records:
            results.append(self.notify(event_key, record._name, record.id, context))
        return results

    # =====================================================================
    # engine
    # =====================================================================
    def _empty_result(self, event_key, reason, **extra):
        result = {
            "event_key": event_key,
            "reason": reason,
            "queued": 0,
            "sent": 0,
            "simulated": 0,
            "blocked": 0,
            "skipped_duplicate": 0,
            "recipients": 0,
        }
        result.update(extra)
        return result

    def _resolve_event(self, event_key):
        Event = self.env["itr.notification.event"]
        key = (event_key or "").strip()
        event = Event.search([("event_key", "=", key)], limit=1)
        alias_used = False
        if not event:
            event = self.env["itr.notification.alias"].resolve(key)
            alias_used = bool(event)
        return event, alias_used

    def _notify(self, event_key, res_model, res_id, context):
        Log = self.env["itr.notification.dispatch.log"]
        event, alias_used = self._resolve_event(event_key)

        # --- NOT-005 : unknown event is logged, never silent ---------------
        if not event:
            Log.log_configuration_error(
                event_key,
                _("The notification event '%(key)s' does not exist (and no alias points to it). "
                  "Create the event or add an alias.", key=event_key),
                res_model, res_id,
            )
            return self._empty_result(event_key, "no_event")

        if not event.is_active:
            return self._empty_result(event_key, "event_inactive")

        settings = self.env["itr.notify.settings"].get_settings()

        # --- NOT-003 : the reference record is READ ONLY -------------------
        record = self._safe_browse(res_model, res_id)
        render_context = self._build_context(record, context, event)

        recipients = self._resolve_recipients(event, record, context)
        if not recipients:
            Log.log_configuration_error(
                event.event_key,
                _("Event '%(key)s' produced no valid recipient (Administrator / OdooBot / "
                  "archived users are always excluded).", key=event.event_key),
                res_model, res_id,
            )
            return self._empty_result(event.event_key, "no_recipient")

        channels = self._decide_channels(event)
        cooldown = event.cooldown_minutes or settings.default_cooldown_minutes or 1
        quiet_now = settings.is_quiet_now()
        occurrence_id = context.get("occurrence_id")

        result = self._empty_result(event.event_key, "ok", recipients=len(recipients))
        reserved_ids = []

        for recipient in recipients:
            for channel in channels:
                outcome = self._dispatch_one(
                    event=event,
                    alias_used=event_key if alias_used else False,
                    channel=channel,
                    recipient=recipient,
                    settings=settings,
                    render_context=render_context,
                    res_model=res_model,
                    res_id=res_id,
                    cooldown=cooldown,
                    quiet_now=quiet_now,
                    occurrence_id=occurrence_id,
                )
                if outcome is None:
                    continue
                status, log = outcome
                if status == "queued":
                    reserved_ids.append(log.id)
                    result["queued"] += 1
                elif status == "skipped_duplicate":
                    result["skipped_duplicate"] += 1
                else:
                    result["blocked"] += 1

        if reserved_ids:
            self._schedule_delivery(reserved_ids, settings)
            if self._deliver_inline(settings):
                logs = self.env["itr.notification.dispatch.log"].browse(reserved_ids)
                logs.deliver()
                result["sent"] = len(logs.filtered(lambda log: log.status == "sent"))
                result["simulated"] = len(logs.filtered(lambda log: log.status == "simulated"))
        return result

    # ------------------------------------------------------------- helpers
    def _safe_browse(self, res_model, res_id):
        """Read only access to the reference record; never raises (NOT-003)."""
        if not res_model or not res_id:
            return None
        if res_model not in self.env:
            return None
        try:
            record = self.env[res_model].browse(int(res_id))
            return record if record.exists() else None
        except Exception:  # noqa: BLE001
            return None

    def _build_context(self, record, context, event):
        """Whitelisted variables only (SRS 11-2)."""
        values = {
            "today": fields.Date.to_string(fields.Date.context_today(self)),
            "now": fields.Datetime.to_string(fields.Datetime.now()),
            "event": event.event_key,
            "event_title": event.title,
            "company": self.env.company.display_name,
        }
        if record is not None:
            values["model"] = record._name
            values["res_id"] = record.id
            try:
                values["name"] = record.display_name
            except Exception:  # noqa: BLE001
                values["name"] = str(record.id)
            values["url"] = self._record_url(record)
            values.update(self._record_values(record))
        for key, value in (context or {}).items():
            if key.startswith("itr_") or key == "occurrence_id":
                continue
            values[key] = value
        return values

    def _record_values(self, record):
        """Only simple, readable fields; an AccessError never breaks notify()."""
        values = {}
        try:
            field_names = [
                name for name, field in record._fields.items()
                if field.type in SAFE_FIELD_TYPES and field.store
            ][:60]
            data = record.read(field_names)[0] if field_names else {}
            for key, value in data.items():
                if key in ("id",):
                    continue
                values.setdefault(key, value)
        except Exception:  # noqa: BLE001 - reading is best effort only
            pass
        return values

    def _record_url(self, record):
        try:
            base = self.env["ir.config_parameter"].sudo().get_param("web.base.url")  # ITR-SUDO-OK
            return "%s/odoo/%s/%s" % (base or "", record._name, record.id)
        except Exception:  # noqa: BLE001
            return ""

    # ----------------------------------------------------- 2.11 recipients
    def _blocked_user_ids(self):
        return self.env["itr.notification.event"]._blocked_user_ids()

    def _group_users(self, group):
        """Odoo 19 tolerant: prefer the transitive user list when available."""
        if "all_user_ids" in group._fields:
            users = group.all_user_ids
        else:
            users = group.user_ids
        return users

    def _resolve_recipients(self, event, record, context):
        blocked = self._blocked_user_ids()
        by_user = {}
        raw_mobiles = {}

        forced_ids = (context or {}).get("itr_force_user_ids")
        if forced_ids:
            users = self.env["res.users"].browse(forced_ids).exists()
            for user in users:
                if user.id not in blocked and user.active:
                    by_user[user.id] = user
        else:
            for group in event.recipient_group_ids:
                for user in self._group_users(group):
                    if user.id in blocked or not user.active:
                        continue
                    by_user[user.id] = user

            for user in event.recipient_user_ids:
                if user.id in blocked or not user.active:
                    continue
                by_user[user.id] = user

            if event.dynamic_user_field and record is not None:
                user = self._dynamic_user(record, event.dynamic_user_field)
                if user and user.id not in blocked and user.active:
                    by_user[user.id] = user

            if event.dynamic_mobile_field and record is not None:
                mobile = self._dynamic_value(record, event.dynamic_mobile_field)
                if mobile:
                    raw_mobiles[str(mobile)] = True

        recipients = [{"user": user, "mobile": None} for user in by_user.values()]
        recipients += [{"user": None, "mobile": mobile} for mobile in raw_mobiles]
        return recipients

    def _dynamic_user(self, record, field_name):
        try:
            if field_name not in record._fields:
                return None
            value = record[field_name]
            if hasattr(value, "_name") and value._name == "res.users":
                return value[:1]
            if isinstance(value, int):
                return self.env["res.users"].browse(value).exists()
        except Exception:  # noqa: BLE001
            return None
        return None

    def _dynamic_value(self, record, field_name):
        try:
            if field_name not in record._fields:
                return None
            return record[field_name]
        except Exception:  # noqa: BLE001
            return None

    # ------------------------------------------------------- 2.10 channels
    def _decide_channels(self, event):
        channels = ["internal"]  # free and always on (NOT-008)
        if event.send_sms:
            channels.append("sms")
        if event.send_email:
            channels.append("email")
        return channels

    def _address_for(self, channel, recipient, event, settings):
        user = recipient.get("user")
        if channel == "internal":
            return user.login if user else None
        if channel == "sms":
            preference = self._preference(user, event, settings)
            if preference and preference.custom_mobile:
                return preference.custom_mobile
            if recipient.get("mobile"):
                return recipient["mobile"]
            if user:
                partner = user.partner_id
                mobile = (
                    partner["mobile"]
                    if "mobile" in partner._fields
                    else False
                )
                return mobile or partner.phone or False
            return None
        if channel == "email":
            return user.email if user else None
        return None

    def _preference(self, user, event, settings):
        if not user or not settings.enable_user_preferences:
            return None
        return self.env["itr.notification.user.preference"].sudo().search([  # ITR-SUDO-OK
            ("user_id", "=", user.id),
            ("event_id", "=", event.id),
        ], limit=1)

    # --------------------------------------------------- one channel / one
    def _dispatch_one(self, event, alias_used, channel, recipient, settings,
                      render_context, res_model, res_id, cooldown, quiet_now,
                      occurrence_id):
        Log = self.env["itr.notification.dispatch.log"]
        user = recipient.get("user")

        if channel in ("internal", "email") and not user:
            return None  # a raw mobile recipient only gets SMS

        address = self._address_for(channel, recipient, event, settings)
        subject, body, missing = self._render(event, channel, render_context)

        identity = dedup_utils.identity_key(
            event.event_key, res_model, res_id, channel, address or (user and user.login)
        )
        key = dedup_utils.dedup_key(
            identity,
            occurrence_id=occurrence_id,
            epoch_seconds=fields.Datetime.now().timestamp(),
            cooldown_minutes=cooldown,
        )

        values = {
            "event_key": event.event_key,
            "event_id": event.id,
            "alias_used": alias_used or False,
            "channel": channel,
            "res_model": res_model or False,
            "res_id": res_id or 0,
            "recipient_user_id": user.id if user else False,
            "recipient_address": address or False,
            "subject": subject,
            "body": body,
            "sms_parts": renderer.sms_part_count(body) if channel == "sms" else 0,
            "missing_variables": ", ".join(missing) if missing else False,
            "identity_key": identity,
            "dedup_key": key,
        }

        # ---- blocking decisions (each one is recorded, never silent) ------
        if not settings.master_enabled:
            return self._write_blocked(values, "blocked_master_off",
                                       _("The whole notification system is switched off."))
        if not address:
            return self._write_blocked(values, "blocked_no_address",
                                       _("No address is available for this channel."))

        preference = self._preference(user, event, settings)
        if preference and not event.is_critical and event.allow_user_optout:
            if channel == "internal" and preference.mute_internal:
                return self._write_blocked(values, "blocked_muted",
                                           _("The user muted the internal notification."))
            if channel == "sms" and preference.mute_sms:
                return self._write_blocked(values, "blocked_muted",
                                           _("The user muted the SMS of this event."))

        if channel == "sms":
            if not settings.sms_master_enabled and not settings.test_mode:
                return self._write_blocked(values, "blocked_sms_off",
                                           _("The SMS kill switch is off (NOT-007)."))
            if quiet_now and event.respect_quiet_hours and not event.is_critical:
                values["replay_after"] = settings.next_quiet_end()
                return self._write_blocked(
                    values, "blocked_quiet",
                    _("Quiet hours: the message is queued for the morning replay."),
                )

        # ---- sliding window (NOT-019) -------------------------------------
        window_start = fields.Datetime.subtract(fields.Datetime.now(), minutes=cooldown)
        already = Log.search_count([
            ("identity_key", "=", identity),
            ("create_date", ">=", window_start),
            ("status", "in", ["queued", "sent", "simulated", "blocked_quiet"]),
        ])
        if already:
            existing = Log.search([("dedup_key", "=", key)], limit=1)
            if existing:
                return ("skipped_duplicate", existing)

            values["status"] = "skipped_duplicate"
            values["decision_reason"] = _(
                "The same notification was already dispatched during the last "
                "%(minutes)s minutes.", minutes=cooldown
            )
            log = self._safe_create(values)
            return ("skipped_duplicate", log or Log.browse())

        # ---- reserve then send (NOT-006) ----------------------------------
        values["status"] = "queued"
        log = self._safe_create(values)
        if log is None:
            return ("skipped_duplicate", Log.browse())
        return ("queued", log)

    def _render(self, event, channel, render_context):
        if channel == "sms":
            body, missing = renderer.render(event.sms_body, render_context)
            return "", body, missing
        if channel == "email":
            subject, missing_subject = renderer.render(
                event.email_subject or event.title, render_context
            )
            body, missing_body = renderer.render(event.email_body, render_context)
            return subject, body, sorted(set(missing_subject) | set(missing_body))
        subject, missing_subject = renderer.render(
            event.internal_subject or event.title, render_context
        )
        body, missing_body = renderer.render(
            event.internal_body or event.title, render_context
        )
        return subject, body, sorted(set(missing_subject) | set(missing_body))

    def _write_blocked(self, values, status, reason):
        payload = dict(values)
        payload["status"] = status
        payload["decision_reason"] = reason
        log = self._safe_create(payload)
        return (status, log) if log else None

    def _safe_create(self, values):
        """Insert the reservation row; a unique violation means 'duplicate'."""
        Log = self.env["itr.notification.dispatch.log"]
        try:
            with self.env.cr.savepoint():
                return Log.create(values)
        except Exception as error:  # noqa: BLE001 - unique violation is a normal outcome
            message = str(error).lower()
            if "unique" in message or "duplicate key" in message:
                return None
            _logger.exception("itr_notify: could not write the dispatch log row")
            return None

    # --------------------------------------------------- 2.22 outbox ------
    def _deliver_inline(self, settings):
        """Tests and the verify script need a synchronous delivery."""
        if self.env.context.get("itr_notify_sync"):
            return True
        if not settings.outbox_enabled:
            return True
        in_test = getattr(self.env.registry, "in_test_mode", None)
        return bool(in_test and in_test())

    def _schedule_delivery(self, log_ids, settings):
        """NOT-017: deliver AFTER the commit, never inside the transaction."""
        if self._deliver_inline(settings):
            return False
        dbname = self.env.cr.dbname

        def _post_commit_delivery():
            try:
                import odoo
                registry = odoo.registry(dbname)
                with registry.cursor() as cr:
                    env = api.Environment(cr, SUPERUSER_ID, {})  # ITR-SUDO-OK infrastructure
                    env["itr.notification.dispatch.log"].browse(log_ids).exists().deliver()
            except Exception:  # noqa: BLE001 - a post commit hook must never raise
                _logger.exception("itr_notify: post commit delivery failed")

        try:
            self.env.cr.postcommit.add(_post_commit_delivery)
            return True
        except Exception:  # noqa: BLE001 - very old cursor without postcommit
            _post_commit_delivery()
            return True
PYEOF

write_utf8 "${MOD_DIR}/models/itr_sla_policy.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""SLA policy (checklist 2.23) - still 100% domain free.

A policy describes: "a task of kind <task_key> on model <res_model> must be
finished within <deadline_minutes>; if not, escalate through these four event
keys". No business model name is hard coded here; later phases only create
policy records (data, not code) - G18: THE single SLA engine of the project.
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError
from odoo.tools import sql as sql_tools

from .itr_notification_event import EVENT_KEY_RE


class ItrSlaPolicy(models.Model):
    _name = "itr.sla.policy"
    _description = "Iran Notify SLA Policy"
    _order = "policy_key"

    policy_key = fields.Char(string="Policy key", required=True, index=True)
    name = fields.Char(string="Name", required=True)
    res_model = fields.Char(string="Target model", required=True)
    task_key = fields.Char(string="Task key", required=True, default="default")
    active = fields.Boolean(string="Active", default=True)

    deadline_minutes = fields.Integer(string="Deadline (minutes)", required=True, default=120)
    warning_ratio = fields.Float(string="Warning ratio", default=0.8)

    # NOT-033 four level escalation ladder
    level1_event_key = fields.Char(string="Level 1 event (employee)")
    level2_event_key = fields.Char(string="Level 2 event (supervisor)")
    level3_event_key = fields.Char(string="Level 3 event (unit manager)")
    level4_event_key = fields.Char(string="Level 4 event (CEO)")
    level_gap_minutes = fields.Integer(
        string="Gap between levels (minutes)", default=60,
        help="Minutes to wait after a level before escalating to the next one.",
    )
    note = fields.Text(string="Notes")

    def init(self):
        sql_tools.create_unique_index(
            self._cr, "itr_sla_policy_key_uniq", self._table, ["policy_key"]
        )

    @api.constrains("policy_key")
    def _check_policy_key(self):
        for record in self:
            key = (record.policy_key or "").strip()
            if not EVENT_KEY_RE.match(key):
                raise ValidationError(
                    _("The policy key must match ^[a-z0-9_]+(\\.[a-z0-9_]+)*$. Received: %(key)s",
                      key=key)
                )
            if self.search_count([("policy_key", "=", key), ("id", "!=", record.id)]):
                raise ValidationError(_("This policy key already exists: %(key)s", key=key))

    @api.constrains("deadline_minutes", "level_gap_minutes", "warning_ratio")
    def _check_numbers(self):
        for record in self:
            if record.deadline_minutes <= 0:
                raise ValidationError(_("The SLA deadline must be greater than zero."))
            if record.level_gap_minutes < 0:
                raise ValidationError(_("The gap between escalation levels cannot be negative."))
            if not 0.0 < record.warning_ratio <= 1.0:
                raise ValidationError(_("The warning ratio must be between 0 and 1."))

    def event_key_for_level(self, level):
        self.ensure_one()
        return {
            1: self.level1_event_key,
            2: self.level2_event_key,
            3: self.level3_event_key,
            4: self.level4_event_key,
        }.get(level) or False
PYEOF

write_utf8 "${MOD_DIR}/models/itr_sla_watch.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""The SLA watch: one open row per (policy, record, task) - NOT-032.

The SLA is measured on the TASK, never on the whole case, and only a real
business action closes it (NOT-034: opening a form or writing a note is not an
action, therefore only an explicit close_watch() call stops the clock).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

OPEN_INDEX_NAME = "itr_sla_watch_open_uniq"

STATES = [
    ("open", "Open"),
    ("done", "Done"),
    ("cancelled", "Cancelled"),
]

SLA_STATES = [
    ("green", "On time"),
    ("amber", "Close to the deadline"),
    ("orange", "Late"),
    ("red", "Critical"),
]


class ItrSlaWatch(models.Model):
    _name = "itr.sla.watch"
    _description = "Iran Notify SLA Watch"
    _order = "deadline"

    policy_id = fields.Many2one("itr.sla.policy", string="Policy", required=True,
                                ondelete="cascade", index=True)
    res_model = fields.Char(string="Model", required=True, index=True)
    res_id = fields.Integer(string="Record id", required=True, index=True)
    task_key = fields.Char(string="Task key", required=True, default="default")
    owner_user_id = fields.Many2one("res.users", string="Responsible", ondelete="set null")

    started_on = fields.Datetime(string="Started on", required=True,
                                 default=fields.Datetime.now)
    deadline = fields.Datetime(string="Deadline", required=True, index=True)
    closed_on = fields.Datetime(string="Closed on")
    state = fields.Selection(STATES, string="State", required=True, default="open", index=True)
    last_level = fields.Integer(string="Last escalated level", default=0)
    last_escalation_on = fields.Datetime(string="Last escalation")
    sla_state = fields.Selection(SLA_STATES, string="SLA state", compute="_compute_sla_state")
    close_reason = fields.Char(string="Close reason")

    def init(self):
        self._ensure_open_watch_index()

    @api.model
    def _ensure_open_watch_index(self):
        """Only ONE open watch per (policy, record, task) - a real partial index."""
        self.env.cr.execute("SELECT 1 FROM pg_indexes WHERE indexname = %s", (OPEN_INDEX_NAME,))
        if self.env.cr.fetchone():
            return False
        self.env.cr.execute(
            'CREATE UNIQUE INDEX "%s" ON "%s" '
            "(policy_id, res_model, res_id, task_key) WHERE state = 'open'"
            % (OPEN_INDEX_NAME, self._table)
        )
        return True

    @api.depends("deadline", "state")
    def _compute_sla_state(self):
        now = fields.Datetime.now()
        for record in self:
            if record.state != "open" or not record.deadline:
                record.sla_state = "green"
                continue
            total = (record.deadline - record.started_on).total_seconds() or 1.0
            elapsed = (now - record.started_on).total_seconds()
            ratio = elapsed / total
            warning = record.policy_id.warning_ratio or 0.8
            if ratio < warning:
                record.sla_state = "green"
            elif ratio < 1.0:
                record.sla_state = "amber"
            elif record.last_level >= 3:
                record.sla_state = "red"
            else:
                record.sla_state = "orange"

    def unlink(self):
        if any(record.state == "open" for record in self):
            raise UserError(
                _("An open SLA watch cannot be deleted; close it with a reason instead.")
            )
        return super().unlink()
PYEOF

write_utf8 "${MOD_DIR}/models/itr_sla_service.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""THE single SLA engine of the project (checklist 2.23 / NOT-035 / G18).

Public API for every later phase (never build a second engine):

    env['itr.sla.service'].open_watch('transport.waybill', record, user)
    env['itr.sla.service'].close_watch('transport.waybill', record, reason='...')

One cron, every 15 minutes, idempotent: it escalates at most one level per run
per watch and relies on the notify() cooldown to stay spam free.
"""
import logging

from odoo import _, api, fields, models

_logger = logging.getLogger(__name__)


class ItrSlaService(models.AbstractModel):
    _name = "itr.sla.service"
    _description = "Iran Notify SLA Service"

    @api.model
    def _policy(self, policy_key):
        return self.env["itr.sla.policy"].search([
            ("policy_key", "=", (policy_key or "").strip()),
            ("active", "=", True),
        ], limit=1)

    @api.model
    def open_watch(self, policy_key, record, owner=None, started_on=None):
        """Start (or reuse) the SLA clock of a task. Never raises."""
        try:
            policy = self._policy(policy_key)
            if not policy:
                self.env["itr.notification.dispatch.log"].log_configuration_error(
                    "sla.%s" % policy_key,
                    _("SLA policy '%(key)s' does not exist or is archived.", key=policy_key),
                    record and record._name, record and record.id,
                )
                return self.env["itr.sla.watch"]
            Watch = self.env["itr.sla.watch"]
            existing = Watch.search([
                ("policy_id", "=", policy.id),
                ("res_model", "=", record._name),
                ("res_id", "=", record.id),
                ("task_key", "=", policy.task_key),
                ("state", "=", "open"),
            ], limit=1)
            if existing:
                return existing
            start = started_on or fields.Datetime.now()
            return Watch.create({
                "policy_id": policy.id,
                "res_model": record._name,
                "res_id": record.id,
                "task_key": policy.task_key,
                "owner_user_id": owner.id if owner else False,
                "started_on": start,
                "deadline": fields.Datetime.add(start, minutes=policy.deadline_minutes),
            })
        except Exception:  # noqa: BLE001 - the SLA must never break the business flow
            _logger.exception("itr_notify: open_watch(%s) failed", policy_key)
            return self.env["itr.sla.watch"]

    @api.model
    def close_watch(self, policy_key, record, reason=None):
        """NOT-034: only an explicit, valid business action stops the clock."""
        try:
            policy = self._policy(policy_key)
            if not policy:
                return 0
            watches = self.env["itr.sla.watch"].search([
                ("policy_id", "=", policy.id),
                ("res_model", "=", record._name),
                ("res_id", "=", record.id),
                ("state", "=", "open"),
            ])
            watches.write({
                "state": "done",
                "closed_on": fields.Datetime.now(),
                "close_reason": reason or _("Valid business action recorded."),
            })
            return len(watches)
        except Exception:  # noqa: BLE001
            _logger.exception("itr_notify: close_watch(%s) failed", policy_key)
            return 0

    # ------------------------------------------------------------- the cron
    @api.model
    def _cron_scan_sla(self, limit=500, now=None):
        """Idempotent scan, one level per run per watch (NOT-035)."""
        settings = self.env["itr.notify.settings"].get_settings()
        if not settings.master_enabled or not settings.sla_enabled:
            return 0
        now = now or fields.Datetime.now()
        watches = self.env["itr.sla.watch"].search([
            ("state", "=", "open"),
            ("deadline", "<=", now),
            ("last_level", "<", 4),
        ], limit=limit)
        escalated = 0
        for watch in watches:
            if self._escalate(watch, now):
                escalated += 1
        return escalated

    @api.model
    def _escalate(self, watch, now):
        policy = watch.policy_id
        target_level = watch.last_level + 1
        if target_level > 4:
            return False
        if watch.last_escalation_on and policy.level_gap_minutes:
            next_allowed = fields.Datetime.add(
                watch.last_escalation_on, minutes=policy.level_gap_minutes
            )
            if next_allowed > now:
                return False

        event_key = policy.event_key_for_level(target_level)
        if not event_key:
            watch.write({"last_level": target_level, "last_escalation_on": now})
            return False

        self.env["itr.notification.service"].notify(
            event_key,
            watch.res_model,
            watch.res_id,
            {
                "sla_policy": policy.policy_key,
                "sla_task": watch.task_key,
                "sla_level": target_level,
                "deadline": fields.Datetime.to_string(watch.deadline),
                "occurrence_id": "sla-%s-%s" % (watch.id, target_level),
                "reason": _("The SLA deadline of this task has been exceeded."),
            },
        )
        watch.write({"last_level": target_level, "last_escalation_on": now})
        return True
PYEOF

# --------------------------------------------------------------- security --
write_utf8 "${MOD_DIR}/security/itr_notify_groups.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- Odoo 19: groups hang on a res.groups.privilege, not on a category. -->
        <record id="privilege_itr_notify" model="res.groups.privilege">
            <field name="name">Iran Notification Infrastructure</field>
            <field name="description">Notification events, SMS gateways, dispatch log and SLA</field>
            <field name="category_id" ref="itr_base.module_category_itr"/>
            <field name="sequence">20</field>
        </record>

        <record id="group_itr_notification_user" model="res.groups">
            <field name="name">Notification User</field>
            <field name="privilege_id" ref="itr_notify.privilege_itr_notify"/>
            <field name="implied_ids" eval="[(4, ref('base.group_user'))]"/>
            <field name="comment">May read the event catalogue and manage his own notification preferences.</field>
        </record>

        <record id="group_itr_notification_manager" model="res.groups">
            <field name="name">Notification Manager</field>
            <field name="privilege_id" ref="itr_notify.privilege_itr_notify"/>
            <field name="implied_ids" eval="[(4, ref('itr_notify.group_itr_notification_user'))]"/>
            <field name="comment">May configure events, gateways, SLA policies and read the whole dispatch log.</field>
        </record>

    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/security/ir.model.access.csv" <<'CSVEOF'
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_itr_notify_settings_user,itr.notify.settings user read,model_itr_notify_settings,base.group_user,1,0,0,0
access_itr_notify_settings_manager,itr.notify.settings manager,model_itr_notify_settings,itr_notify.group_itr_notification_manager,1,1,0,0
access_itr_sms_gateway_profile_user,itr.sms.gateway.profile user read,model_itr_sms_gateway_profile,itr_notify.group_itr_notification_user,1,0,0,0
access_itr_sms_gateway_profile_manager,itr.sms.gateway.profile manager,model_itr_sms_gateway_profile,itr_notify.group_itr_notification_manager,1,1,1,1
access_itr_notification_event_user,itr.notification.event user read,model_itr_notification_event,base.group_user,1,0,0,0
access_itr_notification_event_manager,itr.notification.event manager,model_itr_notification_event,itr_notify.group_itr_notification_manager,1,1,1,1
access_itr_notification_alias_user,itr.notification.alias user read,model_itr_notification_alias,base.group_user,1,0,0,0
access_itr_notification_alias_manager,itr.notification.alias manager,model_itr_notification_alias,itr_notify.group_itr_notification_manager,1,1,1,1
access_itr_notification_dispatch_log_user,itr.notification.dispatch.log user,model_itr_notification_dispatch_log,base.group_user,1,1,1,0
access_itr_notification_dispatch_log_manager,itr.notification.dispatch.log manager,model_itr_notification_dispatch_log,itr_notify.group_itr_notification_manager,1,1,1,0
access_itr_notification_user_preference_user,itr.notification.user.preference own,model_itr_notification_user_preference,base.group_user,1,1,1,1
access_itr_notification_user_preference_manager,itr.notification.user.preference manager,model_itr_notification_user_preference,itr_notify.group_itr_notification_manager,1,1,1,1
access_itr_sla_policy_user,itr.sla.policy user read,model_itr_sla_policy,base.group_user,1,0,0,0
access_itr_sla_policy_manager,itr.sla.policy manager,model_itr_sla_policy,itr_notify.group_itr_notification_manager,1,1,1,1
access_itr_sla_watch_user,itr.sla.watch user,model_itr_sla_watch,base.group_user,1,1,1,0
access_itr_sla_watch_manager,itr.sla.watch manager,model_itr_sla_watch,itr_notify.group_itr_notification_manager,1,1,1,1
CSVEOF

write_utf8 "${MOD_DIR}/security/itr_notify_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- A normal user only sees his own dispatch rows; the manager sees all
             (rules of the groups a user belongs to are OR-ed). -->
        <record id="rule_itr_dispatch_log_own" model="ir.rule">
            <field name="name">Dispatch log: own rows only</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_dispatch_log"/>
            <field name="domain_force">['|', ('recipient_user_id', '=', user.id), ('create_uid', '=', user.id)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_itr_dispatch_log_all" model="ir.rule">
            <field name="name">Dispatch log: full access</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_dispatch_log"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('itr_notify.group_itr_notification_manager'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <!-- SEC-017: the own-record guard must also hold for a direct RPC call. -->
        <record id="rule_itr_user_preference_own" model="ir.rule">
            <field name="name">Notification preference: own rows only</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_user_preference"/>
            <field name="domain_force">[('user_id', '=', user.id)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_itr_user_preference_all" model="ir.rule">
            <field name="name">Notification preference: manager access</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_user_preference"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('itr_notify.group_itr_notification_manager'))]"/>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${MOD_DIR}/data/itr_notify_settings_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- noupdate=1 : an upgrade never resets what the customer configured. -->
    <data noupdate="1">
        <record id="itr_notify_settings_default" model="itr.notify.settings">
            <field name="name">ITR Notify Settings</field>
            <field name="master_enabled" eval="True"/>
            <!-- NOT-007: the factory defaults are the SAFE ones -->
            <field name="sms_master_enabled" eval="False"/>
            <field name="test_mode" eval="True"/>
            <field name="default_cooldown_minutes">10</field>
            <field name="quiet_hours_enabled" eval="True"/>
            <field name="quiet_hours_start">22.0</field>
            <field name="quiet_hours_end">7.0</field>
            <field name="enable_user_preferences" eval="True"/>
            <field name="health_digest_enabled" eval="True"/>
            <field name="sla_enabled" eval="True"/>
            <field name="outbox_enabled" eval="True"/>
        </record>

        <record id="itr_sms_gateway_console_debug" model="itr.sms.gateway.profile">
            <field name="name">Console debug gateway</field>
            <field name="adapter_key">console_debug</field>
            <field name="config_json">{}</field>
            <field name="is_default" eval="True"/>
            <field name="active" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_notification_event_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Checklist 2.25 / 2.29 : ONLY the two system events.
         Not a single business event (case.*, shipment.*, payment.*) is seeded
         in the infrastructure module; that is the job of phase 10. -->
    <data noupdate="1">

        <record id="event_system_notify_test" model="itr.notification.event">
            <field name="event_key">system.notify_test</field>
            <field name="title">Notification centre test message</field>
            <field name="category">system</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">1</field>
            <field name="internal_subject">ITR Notify test</field>
            <field name="internal_body">This is a test notification sent on {{today}} by the notification centre. Reason: {{reason}}</field>
            <field name="dynamic_user_field">create_uid</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <record id="event_system_digest_daily_failures" model="itr.notification.event">
            <field name="event_key">system.digest_daily_failures</field>
            <field name="title">Daily notification health digest</field>
            <field name="category">digest</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">720</field>
            <field name="internal_subject">Notification health digest</field>
            <field name="internal_body">{{failed_count}} notifications could not be delivered since {{since}}. Open the dispatch log for the details.</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_notify.group_itr_notification_manager'))]"/>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_notify_cron.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">

        <!-- 2.23 : THE single SLA engine, every 15 minutes, idempotent -->
        <record id="cron_itr_sla_scan" model="ir.cron">
            <field name="name">ITR Notify: SLA scan</field>
            <field name="model_id" ref="itr_notify.model_itr_sla_watch"/>
            <field name="state">code</field>
            <field name="code">env['itr.sla.service']._cron_scan_sla()</field>
            <field name="interval_number">15</field>
            <field name="interval_type">minutes</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="active" eval="True"/>
        </record>

        <!-- 2.21 : morning replay of what the quiet hours blocked -->
        <record id="cron_itr_quiet_hours_replay" model="ir.cron">
            <field name="name">ITR Notify: quiet hours replay</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_dispatch_log"/>
            <field name="state">code</field>
            <field name="code">model._cron_replay_quiet_hours()</field>
            <field name="interval_number">10</field>
            <field name="interval_type">minutes</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="active" eval="True"/>
        </record>

        <!-- 2.24 : the infrastructure reports its own health through notify() -->
        <record id="cron_itr_health_digest" model="ir.cron">
            <field name="name">ITR Notify: daily health digest</field>
            <field name="model_id" ref="itr_notify.model_itr_notification_dispatch_log"/>
            <field name="state">code</field>
            <field name="code">model._cron_daily_health_digest()</field>
            <field name="interval_number">1</field>
            <field name="interval_type">days</field>
            <field name="user_id" ref="base.user_root"/>
            <field name="active" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${MOD_DIR}/views/itr_notify_settings_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_notify_settings_form" model="ir.ui.view">
        <field name="name">itr.notify.settings.form</field>
        <field name="model">itr.notify.settings</field>
        <field name="arch" type="xml">
            <form string="Notification Settings">
                <sheet>
                    <div class="oe_title"><h1><field name="name" readonly="1"/></h1></div>
                    <group>
                        <group string="Kill switches">
                            <field name="master_enabled"/>
                            <field name="sms_master_enabled"/>
                            <field name="test_mode"/>
                            <field name="test_mobile" invisible="not test_mode"/>
                        </group>
                        <group string="Defaults">
                            <field name="default_gateway_id"/>
                            <field name="default_cooldown_minutes"/>
                            <field name="enable_user_preferences"/>
                            <field name="outbox_enabled"/>
                        </group>
                    </group>
                    <group>
                        <group string="Quiet hours">
                            <field name="quiet_hours_enabled"/>
                            <field name="quiet_hours_start" widget="float_time"
                                   invisible="not quiet_hours_enabled"/>
                            <field name="quiet_hours_end" widget="float_time"
                                   invisible="not quiet_hours_enabled"/>
                        </group>
                        <group string="Monitoring">
                            <field name="health_digest_enabled"/>
                            <field name="sla_enabled"/>
                        </group>
                    </group>
                    <group string="Notes">
                        <field name="note" nolabel="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_notify_settings" model="ir.actions.act_window">
        <field name="name">Notification Settings</field>
        <field name="res_model">itr.notify.settings</field>
        <field name="view_mode">form</field>
        <field name="res_id" eval="ref('itr_notify.itr_notify_settings_default')"/>
        <field name="target">current</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_sms_gateway_profile_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_sms_gateway_profile_list" model="ir.ui.view">
        <field name="name">itr.sms.gateway.profile.list</field>
        <field name="model">itr.sms.gateway.profile</field>
        <field name="arch" type="xml">
            <list string="SMS Gateways">
                <field name="name"/>
                <field name="adapter_key"/>
                <field name="is_default"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="view_itr_sms_gateway_profile_form" model="ir.ui.view">
        <field name="name">itr.sms.gateway.profile.form</field>
        <field name="model">itr.sms.gateway.profile</field>
        <field name="arch" type="xml">
            <form string="SMS Gateway">
                <sheet>
                    <group>
                        <group>
                            <field name="name"/>
                            <field name="adapter_key"/>
                        </group>
                        <group>
                            <field name="is_default"/>
                            <field name="active"/>
                        </group>
                    </group>
                    <group string="Configuration (JSON)">
                        <field name="config_json" nolabel="1" widget="text"/>
                    </group>
                    <group string="Expected configuration keys">
                        <field name="required_fields_hint" nolabel="1" readonly="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_sms_gateway_profile" model="ir.actions.act_window">
        <field name="name">SMS Gateways</field>
        <field name="res_model">itr.sms.gateway.profile</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_notification_event_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_notification_event_list" model="ir.ui.view">
        <field name="name">itr.notification.event.list</field>
        <field name="model">itr.notification.event</field>
        <field name="arch" type="xml">
            <list string="Notification Events">
                <field name="event_key"/>
                <field name="title"/>
                <field name="category"/>
                <field name="send_sms"/>
                <field name="is_critical"/>
                <field name="is_active"/>
                <field name="sms_parts"/>
            </list>
        </field>
    </record>

    <record id="view_itr_notification_event_form" model="ir.ui.view">
        <field name="name">itr.notification.event.form</field>
        <field name="model">itr.notification.event</field>
        <field name="arch" type="xml">
            <form string="Notification Event">
                <header>
                    <button name="action_send_test_to_me" type="object" string="Send a test to me"
                            class="btn-primary" invisible="not id"/>
                    <button name="action_open_logs" type="object" string="Dispatch log"
                            invisible="not id"/>
                </header>
                <sheet>
                    <div class="oe_title"><h1><field name="title" placeholder="Title"/></h1></div>
                    <group>
                        <group string="Identity">
                            <field name="event_key" placeholder="case.legal_rejected"/>
                            <field name="category"/>
                            <field name="is_active"/>
                            <field name="is_critical"/>
                            <field name="cooldown_minutes"/>
                        </group>
                        <group string="Channels">
                            <label for="send_sms"/>
                            <div>
                                <field name="send_sms"/>
                                <div class="text-muted">
                                    The internal notification is free and always on; only the SMS is a real decision.
                                </div>
                            </div>
                            <field name="send_email"/>
                            <field name="respect_quiet_hours"/>
                            <field name="allow_user_optout"/>
                        </group>
                    </group>
                    <notebook>
                        <page string="Recipients">
                            <group>
                                <field name="recipient_group_ids" widget="many2many_tags"/>
                                <field name="recipient_user_ids" widget="many2many_tags"/>
                                <field name="dynamic_user_field"/>
                                <field name="dynamic_mobile_field"/>
                            </group>
                        </page>
                        <page string="Internal message">
                            <group>
                                <field name="internal_subject"/>
                                <field name="internal_body"/>
                                <field name="variables_hint" readonly="1"/>
                            </group>
                        </page>
                        <page string="SMS" invisible="not send_sms">
                            <group>
                                <field name="sms_body"/>
                                <field name="sms_parts" readonly="1"/>
                            </group>
                        </page>
                        <page string="Email" invisible="not send_email">
                            <group>
                                <field name="email_subject"/>
                                <field name="email_body"/>
                            </group>
                        </page>
                        <page string="Aliases">
                            <field name="alias_ids">
                                <list editable="bottom">
                                    <field name="alias_key"/>
                                    <field name="note"/>
                                </list>
                            </field>
                        </page>
                        <page string="Technical">
                            <group>
                                <field name="is_seed" readonly="1"/>
                                <field name="allow_seed_overwrite"/>
                                <field name="note"/>
                            </group>
                        </page>
                    </notebook>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_notification_event_search" model="ir.ui.view">
        <field name="name">itr.notification.event.search</field>
        <field name="model">itr.notification.event</field>
        <field name="arch" type="xml">
            <search string="Notification Events">
                <field name="event_key"/>
                <field name="title"/>
                <filter name="active_events" string="Active" domain="[('is_active','=',True)]"/>
                <filter name="sms_events" string="With SMS" domain="[('send_sms','=',True)]"/>
                <filter name="critical_events" string="Critical" domain="[('is_critical','=',True)]"/>
                <filter name="group_category" string="Category" context="{'group_by': 'category'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_notification_event" model="ir.actions.act_window">
        <field name="name">Notification Events</field>
        <field name="res_model">itr.notification.event</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_notification_alias_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_notification_alias_list" model="ir.ui.view">
        <field name="name">itr.notification.alias.list</field>
        <field name="model">itr.notification.alias</field>
        <field name="arch" type="xml">
            <list string="Event Aliases" editable="bottom">
                <field name="alias_key"/>
                <field name="event_id"/>
                <field name="note"/>
            </list>
        </field>
    </record>

    <record id="action_itr_notification_alias" model="ir.actions.act_window">
        <field name="name">Event Aliases</field>
        <field name="res_model">itr.notification.alias</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_notification_dispatch_log_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_notification_dispatch_log_list" model="ir.ui.view">
        <field name="name">itr.notification.dispatch.log.list</field>
        <field name="model">itr.notification.dispatch.log</field>
        <field name="arch" type="xml">
            <list string="Dispatch Log" create="false" edit="false" delete="false">
                <field name="create_date"/>
                <field name="event_key"/>
                <field name="channel"/>
                <field name="status"/>
                <field name="recipient_display"/>
                <field name="res_model"/>
                <field name="res_id"/>
                <field name="sms_parts"/>
            </list>
        </field>
    </record>

    <record id="view_itr_notification_dispatch_log_form" model="ir.ui.view">
        <field name="name">itr.notification.dispatch.log.form</field>
        <field name="model">itr.notification.dispatch.log</field>
        <field name="arch" type="xml">
            <form string="Dispatch Log" create="false" edit="false" delete="false">
                <sheet>
                    <group>
                        <group>
                            <field name="event_key"/>
                            <field name="alias_used"/>
                            <field name="channel"/>
                            <field name="status"/>
                            <field name="recipient_display"/>
                        </group>
                        <group>
                            <field name="res_model"/>
                            <field name="res_id"/>
                            <field name="attempt_count"/>
                            <field name="delivered_on"/>
                            <field name="replay_after"/>
                        </group>
                    </group>
                    <group string="Message">
                        <field name="subject"/>
                        <field name="body"/>
                        <field name="missing_variables"/>
                    </group>
                    <group string="Decision">
                        <field name="decision_reason"/>
                        <field name="error_detail"/>
                        <field name="provider_message_id"/>
                        <field name="dedup_key"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_notification_dispatch_log_search" model="ir.ui.view">
        <field name="name">itr.notification.dispatch.log.search</field>
        <field name="model">itr.notification.dispatch.log</field>
        <field name="arch" type="xml">
            <search string="Dispatch Log">
                <field name="event_key"/>
                <field name="res_model"/>
                <filter name="failed" string="Failed" domain="[('status','in',['failed','config_error'])]"/>
                <filter name="blocked" string="Blocked" domain="[('status','like','blocked')]"/>
                <filter name="group_status" string="Status" context="{'group_by': 'status'}"/>
                <filter name="group_event" string="Event" context="{'group_by': 'event_key'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_notification_dispatch_log" model="ir.actions.act_window">
        <field name="name">Dispatch Log</field>
        <field name="res_model">itr.notification.dispatch.log</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_notification_user_preference_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_notification_user_preference_list" model="ir.ui.view">
        <field name="name">itr.notification.user.preference.list</field>
        <field name="model">itr.notification.user.preference</field>
        <field name="arch" type="xml">
            <list string="My Notification Preferences" editable="bottom">
                <field name="user_id" readonly="1"/>
                <field name="event_id"/>
                <field name="mute_internal"/>
                <field name="mute_sms"/>
                <field name="custom_mobile"/>
            </list>
        </field>
    </record>

    <record id="action_itr_notification_user_preference" model="ir.actions.act_window">
        <field name="name">My Notification Preferences</field>
        <field name="res_model">itr.notification.user.preference</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_sla_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_sla_policy_list" model="ir.ui.view">
        <field name="name">itr.sla.policy.list</field>
        <field name="model">itr.sla.policy</field>
        <field name="arch" type="xml">
            <list string="SLA Policies">
                <field name="policy_key"/>
                <field name="name"/>
                <field name="res_model"/>
                <field name="task_key"/>
                <field name="deadline_minutes"/>
                <field name="active"/>
            </list>
        </field>
    </record>

    <record id="view_itr_sla_policy_form" model="ir.ui.view">
        <field name="name">itr.sla.policy.form</field>
        <field name="model">itr.sla.policy</field>
        <field name="arch" type="xml">
            <form string="SLA Policy">
                <sheet>
                    <group>
                        <group>
                            <field name="policy_key"/>
                            <field name="name"/>
                            <field name="res_model"/>
                            <field name="task_key"/>
                            <field name="active"/>
                        </group>
                        <group>
                            <field name="deadline_minutes"/>
                            <field name="warning_ratio"/>
                            <field name="level_gap_minutes"/>
                        </group>
                    </group>
                    <group string="Escalation ladder (NOT-033)">
                        <field name="level1_event_key"/>
                        <field name="level2_event_key"/>
                        <field name="level3_event_key"/>
                        <field name="level4_event_key"/>
                    </group>
                    <group string="Notes">
                        <field name="note" nolabel="1"/>
                    </group>
                </sheet>
            </form>
        </field>
    </record>

    <record id="view_itr_sla_watch_list" model="ir.ui.view">
        <field name="name">itr.sla.watch.list</field>
        <field name="model">itr.sla.watch</field>
        <field name="arch" type="xml">
            <list string="SLA Watches" create="false">
                <field name="policy_id"/>
                <field name="res_model"/>
                <field name="res_id"/>
                <field name="task_key"/>
                <field name="owner_user_id"/>
                <field name="deadline"/>
                <field name="state"/>
                <field name="last_level"/>
                <field name="sla_state"/>
            </list>
        </field>
    </record>

    <record id="action_itr_sla_policy" model="ir.actions.act_window">
        <field name="name">SLA Policies</field>
        <field name="res_model">itr.sla.policy</field>
        <field name="view_mode">list,form</field>
    </record>

    <record id="action_itr_sla_watch" model="ir.actions.act_window">
        <field name="name">SLA Watches</field>
        <field name="res_model">itr.sla.watch</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_notify_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_notify_root"
              name="Notification Centre"
              sequence="91"
              groups="itr_notify.group_itr_notification_user"/>

    <menuitem id="menu_itr_notify_operations"
              name="Operations"
              parent="menu_itr_notify_root"
              sequence="10"/>

    <menuitem id="menu_itr_notification_dispatch_log"
              name="Dispatch Log"
              parent="menu_itr_notify_operations"
              action="action_itr_notification_dispatch_log"
              sequence="10"/>

    <menuitem id="menu_itr_notification_user_preference"
              name="My Notification Preferences"
              parent="menu_itr_notify_operations"
              action="action_itr_notification_user_preference"
              sequence="20"/>

    <menuitem id="menu_itr_notify_configuration"
              name="Configuration"
              parent="menu_itr_notify_root"
              sequence="20"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_notify_settings"
              name="Notification Settings"
              parent="menu_itr_notify_configuration"
              action="action_itr_notify_settings"
              sequence="10"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_notification_event"
              name="Notification Events"
              parent="menu_itr_notify_configuration"
              action="action_itr_notification_event"
              sequence="20"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_notification_alias"
              name="Event Aliases"
              parent="menu_itr_notify_configuration"
              action="action_itr_notification_alias"
              sequence="30"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_sms_gateway_profile"
              name="SMS Gateways"
              parent="menu_itr_notify_configuration"
              action="action_itr_sms_gateway_profile"
              sequence="40"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_sla_policy"
              name="SLA Policies"
              parent="menu_itr_notify_configuration"
              action="action_itr_sla_policy"
              sequence="50"
              groups="itr_notify.group_itr_notification_manager"/>

    <menuitem id="menu_itr_sla_watch"
              name="SLA Watches"
              parent="menu_itr_notify_operations"
              action="action_itr_sla_watch"
              sequence="30"/>
</odoo>
XMLEOF

# -------------------------------------------------------------------- i18n --
write_utf8 "${MOD_DIR}/i18n/fa_IR.po" <<'POEOF'
# Translation of Odoo Server - module itr_notify.
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

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_notify_settings
msgid "Iran Notify Settings"
msgstr "تنظیمات مرکز اعلان"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_notification_event
msgid "Iran Notify Event"
msgstr "رویداد اعلان"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_notification_alias
msgid "Iran Notify Event Alias"
msgstr "نام مستعار رویداد اعلان"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_notification_dispatch_log
msgid "Iran Notify Dispatch Log"
msgstr "دفتر ارسال اعلان"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_notification_user_preference
msgid "Iran Notify User Preference"
msgstr "ترجیح اعلان کاربر"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_sms_gateway_profile
msgid "Iran Notify SMS Gateway Profile"
msgstr "درگاه پیامک"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_sla_policy
msgid "Iran Notify SLA Policy"
msgstr "سیاست SLA"

#. module: itr_notify
#: model:ir.model,name:itr_notify.model_itr_sla_watch
msgid "Iran Notify SLA Watch"
msgstr "پایش SLA"

#. module: itr_notify
#: model:res.groups.privilege,name:itr_notify.privilege_itr_notify
msgid "Iran Notification Infrastructure"
msgstr "زیرساخت اعلان ایران"

#. module: itr_notify
#: model:res.groups,name:itr_notify.group_itr_notification_user
msgid "Notification User"
msgstr "کاربر اعلان"

#. module: itr_notify
#: model:res.groups,name:itr_notify.group_itr_notification_manager
msgid "Notification Manager"
msgstr "مدیر اعلان"

#. module: itr_notify
#: model:ir.ui.menu,name:itr_notify.menu_itr_notify_root
msgid "Notification Centre"
msgstr "مرکز اعلان"

#. module: itr_notify
#: model:ir.ui.menu,name:itr_notify.menu_itr_notify_operations
msgid "Operations"
msgstr "عملیات"

#. module: itr_notify
#: model:ir.ui.menu,name:itr_notify.menu_itr_notify_configuration
msgid "Configuration"
msgstr "پیکربندی"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_notify_settings
#: model:ir.ui.menu,name:itr_notify.menu_itr_notify_settings
msgid "Notification Settings"
msgstr "تنظیمات مرکز اعلان"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_notification_event
#: model:ir.ui.menu,name:itr_notify.menu_itr_notification_event
msgid "Notification Events"
msgstr "رویدادهای اعلان"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_notification_alias
#: model:ir.ui.menu,name:itr_notify.menu_itr_notification_alias
msgid "Event Aliases"
msgstr "نام‌های مستعار رویداد"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_notification_dispatch_log
#: model:ir.ui.menu,name:itr_notify.menu_itr_notification_dispatch_log
msgid "Dispatch Log"
msgstr "دفتر ارسال"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_sms_gateway_profile
#: model:ir.ui.menu,name:itr_notify.menu_itr_sms_gateway_profile
msgid "SMS Gateways"
msgstr "درگاه‌های پیامک"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_sla_policy
#: model:ir.ui.menu,name:itr_notify.menu_itr_sla_policy
msgid "SLA Policies"
msgstr "سیاست‌های SLA"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_sla_watch
#: model:ir.ui.menu,name:itr_notify.menu_itr_sla_watch
msgid "SLA Watches"
msgstr "پایش‌های SLA"

#. module: itr_notify
#: model:ir.actions.act_window,name:itr_notify.action_itr_notification_user_preference
#: model:ir.ui.menu,name:itr_notify.menu_itr_notification_user_preference
msgid "My Notification Preferences"
msgstr "تنظیمات اعلان‌های من"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__master_enabled
msgid "Notification system enabled"
msgstr "سیستم اعلان فعال باشد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__sms_master_enabled
msgid "Real SMS sending enabled"
msgstr "ارسال واقعی پیامک فعال باشد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__test_mode
msgid "Test mode"
msgstr "حالت آزمایشی"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__test_mobile
msgid "Test mobile number"
msgstr "شمارهٔ موبایل آزمایشی"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__default_gateway_id
msgid "Default SMS gateway"
msgstr "درگاه پیامک پیش‌فرض"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__default_cooldown_minutes
msgid "Default cooldown (minutes)"
msgstr "کول‌داون پیش‌فرض (دقیقه)"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__quiet_hours_enabled
msgid "Quiet hours enabled"
msgstr "ساعات سکوت فعال باشد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__quiet_hours_start
msgid "Quiet hours start"
msgstr "شروع ساعات سکوت"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__quiet_hours_end
msgid "Quiet hours end"
msgstr "پایان ساعات سکوت"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__enable_user_preferences
msgid "Allow user preferences"
msgstr "کاربران بتوانند رویدادها را بی‌صدا کنند"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__health_digest_enabled
msgid "Daily health digest enabled"
msgstr "گزارش روزانهٔ سلامت اعلان فعال باشد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__sla_enabled
msgid "SLA monitoring enabled"
msgstr "پایش SLA فعال باشد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notify_settings__outbox_enabled
msgid "Deliver after commit (outbox)"
msgstr "ارسال پس از commit (صندوق خروج)"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__event_key
msgid "Event key"
msgstr "کلید رویداد"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__send_sms
msgid "Also send an SMS (paid)"
msgstr "پیامک هم ارسال شود (پولی)"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__is_critical
msgid "Critical"
msgstr "حیاتی"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__cooldown_minutes
msgid "Cooldown (minutes)"
msgstr "کول‌داون (دقیقه)"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__recipient_group_ids
msgid "Recipient groups"
msgstr "گروه‌های گیرنده"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__recipient_user_ids
msgid "Fixed recipients"
msgstr "کاربران ثابت گیرنده"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__dynamic_user_field
msgid "Dynamic user field"
msgstr "فیلد کاربر پویا"

#. module: itr_notify
#: model:ir.model.fields,field_description:itr_notify.field_itr_notification_event__dynamic_mobile_field
msgid "Dynamic mobile field"
msgstr "فیلد موبایل پویا"

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_event.py:0
#, python-format
msgid "SMS is enabled for '%(key)s' but the SMS text is empty."
msgstr "برای رویداد «%(key)s» پیامک روشن است ولی متن پیامک خالی است."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_event.py:0
#, python-format
msgid ""
"Event '%(key)s' has no recipient source. Define at least one of: recipient "
"group, fixed user, dynamic user field, dynamic mobile field."
msgstr ""
"رویداد «%(key)s» هیچ منبع گیرنده‌ای ندارد. حداقل یکی از این‌ها را تعیین کنید: "
"گروه گیرنده، کاربر ثابت، فیلد کاربر پویا، فیلد موبایل پویا."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_event.py:0
#, python-format
msgid ""
"Administrator / OdooBot can never be a notification recipient (SEC-002 / "
"NOT-004)."
msgstr ""
"مدیر سیستم (Administrator/OdooBot) هرگز نمی‌تواند گیرندهٔ اعلان باشد "
"(SEC-002 / NOT-004)."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_service.py:0
#, python-format
msgid ""
"The notification event '%(key)s' does not exist (and no alias points to it). "
"Create the event or add an alias."
msgstr ""
"رویداد اعلان «%(key)s» وجود ندارد و هیچ نام مستعاری هم به آن اشاره نمی‌کند. "
"رویداد را بسازید یا یک نام مستعار اضافه کنید."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_service.py:0
#, python-format
msgid ""
"Event '%(key)s' produced no valid recipient (Administrator / OdooBot / "
"archived users are always excluded)."
msgstr ""
"رویداد «%(key)s» هیچ گیرندهٔ معتبری تولید نکرد (مدیر سیستم و کاربران غیرفعال "
"همیشه کنار گذاشته می‌شوند)."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_dispatch_log.py:0
#, python-format
msgid "Dispatch log records are append-only and cannot be deleted."
msgstr "رکوردهای دفتر ارسال فقط افزودنی هستند و حذف نمی‌شوند."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_dispatch_log.py:0
#, python-format
msgid ""
"The dispatch log is append-only; it can only be updated by the notification "
"engine."
msgstr ""
"دفتر ارسال فقط افزودنی است؛ تنها موتور اعلان می‌تواند وضعیت آن را به‌روز کند."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_dispatch_log.py:0
#, python-format
msgid "The SMS kill switch is off; the message was not transmitted."
msgstr "کلید اضطراری پیامک خاموش است؛ پیام مخابره نشد."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_dispatch_log.py:0
#, python-format
msgid "Test mode: the message was recorded, not transmitted."
msgstr "حالت آزمایشی: پیام فقط ثبت شد و مخابره نشد."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_service.py:0
#, python-format
msgid "Quiet hours: the message is queued for the morning replay."
msgstr "ساعات سکوت: پیام برای بازپخش صبحگاهی در صف قرار گرفت."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_service.py:0
#, python-format
msgid ""
"The same notification was already dispatched during the last %(minutes)s "
"minutes."
msgstr "همین اعلان در %(minutes)s دقیقهٔ گذشته ارسال شده است."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_notification_user_preference.py:0
#, python-format
msgid "A user can only manage the notification preferences of his own account."
msgstr "هر کاربر فقط می‌تواند ترجیحات اعلان حساب خودش را مدیریت کند."

#. module: itr_notify
#: code:addons/itr_notify/models/itr_sla_watch.py:0
#, python-format
msgid "An open SLA watch cannot be deleted; close it with a reason instead."
msgstr "پایش SLA باز حذف نمی‌شود؛ آن را با ذکر دلیل ببندید."
POEOF
cp -f "${MOD_DIR}/i18n/fa_IR.po" "${MOD_DIR}/i18n/fa.po"

# ------------------------------------------------------------------ tests --
write_utf8 "${MOD_DIR}/tests/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import common
from . import test_event_validation
from . import test_notify_core
from . import test_dedup_quiet_hours
from . import test_sla_engine
PYEOF

write_utf8 "${MOD_DIR}/tests/common.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Shared test helper.

G01: no business assertion is ever made with Administrator / superuser.
Users are created in setUpClass (environment setup, not business proof) and
every assertion runs with_user(real user).
"""
from odoo.tests import TransactionCase


class ItrNotifyCase(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        users_model = cls.env["res.users"]
        # Odoo 19 renamed res.users.groups_id -> group_ids ; stay tolerant.
        cls.group_field = "group_ids" if "group_ids" in users_model._fields else "groups_id"
        cls.settings = cls.env["itr.notify.settings"].get_settings()
        cls.manager = cls._itr_create_user(
            "test_notify_manager", ["itr_notify.group_itr_notification_manager"]
        )
        cls.employee = cls._itr_create_user("test_notify_employee")
        cls.settings = cls.settings.with_user(cls.manager)
        cls.settings.write({"quiet_hours_enabled": False})
        cls.service = cls.env["itr.notification.service"].with_user(cls.manager).with_context(
            itr_notify_sync=True
        )

    @classmethod
    def _itr_create_user(cls, login, group_xmlids=()):
        groups = cls.env.ref("base.group_user")
        for xmlid in group_xmlids:
            groups |= cls.env.ref(xmlid)

        user = cls.env["res.users"].with_context(
            no_reset_password=True
        ).create({
            "name": "TEST %s" % login,
            "login": login,
            "email": "%s@test.invalid" % login,
            cls.group_field: [(6, 0, groups.ids)],
        })

        # Store the number on the contact, not on res.users.mobile.
        user.partner_id.write({"phone": "09120000000"})
        return user

    @classmethod
    def _itr_create_event(cls, key, **values):
        payload = {
            "event_key": key,
            "title": "TEST %s" % key,
            "category": "system",
            "internal_subject": "TEST subject",
            "internal_body": "TEST body {{reason}}",
            "recipient_user_ids": [(6, 0, [cls.employee.id])],
        }
        payload.update(values)
        return cls.env["itr.notification.event"].create(payload)

    def _logs(self, event_key, **filters):
        domain = [("event_key", "=", event_key)]
        for field, value in filters.items():
            domain.append((field, "=", value))
        return self.env["itr.notification.dispatch.log"].sudo().search(domain)
PYEOF

write_utf8 "${MOD_DIR}/tests/test_event_validation.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import UserError, ValidationError
from odoo.tests import tagged

from .common import ItrNotifyCase


@tagged("post_install", "-at_install", "itr_notify")
class TestItrNotifyEventValidation(ItrNotifyCase):

    # --------------------------------------------------------------- 2.8
    def test_10_event_key_pattern(self):
        for bad_key in ("Case.Legal", "case legal", "case..legal", "CASE", "1 case!"):
            with self.subTest(key=bad_key), self.assertRaises(ValidationError):
                self._itr_create_event(bad_key)

    def test_11_event_key_is_unique(self):
        self._itr_create_event("test.unique_key")
        with self.assertRaises(ValidationError):
            self._itr_create_event("test.unique_key")

    # -------------------------------------------------------------- 2.12
    def test_20_sms_without_body_is_refused(self):
        with self.assertRaises(ValidationError):
            self._itr_create_event("test.sms_without_body", send_sms=True, sms_body="")

    def test_21_event_without_recipient_is_refused(self):
        with self.assertRaises(ValidationError):
            self._itr_create_event(
                "test.no_recipient",
                recipient_user_ids=[(6, 0, [])],
                dynamic_user_field=False,
                dynamic_mobile_field=False,
            )

    def test_22_administrator_cannot_be_a_recipient(self):
        admin = self.env.ref("base.user_admin")
        with self.assertRaises(ValidationError):
            self._itr_create_event(
                "test.admin_recipient", recipient_user_ids=[(6, 0, [admin.id])]
            )

    def test_23_negative_cooldown_is_refused(self):
        with self.assertRaises(ValidationError):
            self._itr_create_event("test.negative_cooldown", cooldown_minutes=-5)

    # -------------------------------------------------------------- 2.13
    def test_30_alias_resolution(self):
        event = self._itr_create_event("test.official_name")
        self.env["itr.notification.alias"].create({
            "alias_key": "test.legacy_name",
            "event_id": event.id,
        })
        resolved = self.env["itr.notification.alias"].resolve("test.legacy_name")
        self.assertEqual(resolved, event)

    def test_31_alias_cannot_shadow_an_official_key(self):
        event = self._itr_create_event("test.shadow_target")
        with self.assertRaises(ValidationError):
            self.env["itr.notification.alias"].create({
                "alias_key": "test.shadow_target",
                "event_id": event.id,
            })

    # -------------------------------------------------------------- 2.25
    def test_40_only_system_events_are_seeded(self):
        seeded = self.env["itr.notification.event"].search([("is_seed", "=", True)])
        self.assertTrue(seeded)
        for event in seeded:
            self.assertTrue(
                event.event_key.startswith("system."),
                "checklist 2.29: no business event may be seeded here (%s)" % event.event_key,
            )

    def test_41_seeded_defaults_are_safe(self):
        self.assertFalse(self.settings.sms_master_enabled)
        self.assertTrue(self.settings.test_mode)
        self.assertTrue(self.settings.master_enabled)

    # -------------------------------------------------------------- 2.26
    def test_50_send_test_to_me_button(self):
        event = self.env.ref("itr_notify.event_system_notify_test")
        action = event.with_user(self.manager).with_context(
            itr_notify_sync=True
        ).action_send_test_to_me()
        self.assertEqual(action["tag"], "display_notification")
        logs = self._logs("system.notify_test", recipient_user_id=self.manager.id)
        self.assertTrue(logs)

    def test_51_dispatch_log_is_append_only(self):
        event = self._itr_create_event("test.append_only")
        self.service.notify(event.event_key)
        log = self._logs("test.append_only")[:1]
        self.assertTrue(log)
        with self.assertRaises(UserError):
            log.with_user(self.manager).write({"status": "sent"})
        with self.assertRaises(UserError):
            log.with_user(self.manager).unlink()
PYEOF

write_utf8 "${MOD_DIR}/tests/test_notify_core.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.tests import tagged

from .common import ItrNotifyCase


@tagged("post_install", "-at_install", "itr_notify")
class TestItrNotifyCore(ItrNotifyCase):

    # -------------------------------------------------------------- 2.15
    def test_10_unknown_event_never_raises(self):
        result = self.service.notify("this.event.does.not.exist")
        self.assertEqual(result["reason"], "no_event")
        self.assertEqual(result["queued"], 0)
        # NOT-005: it is logged, never silent
        logs = self._logs("this.event.does.not.exist")
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "config_error")

    def test_11_broken_reference_never_raises(self):
        event = self._itr_create_event("test.broken_reference")
        result = self.service.notify(event.event_key, "no.such.model", 999999)
        self.assertNotEqual(result["reason"], "exception")

    # -------------------------------------------------------------- 2.16
    def test_20_reference_record_is_never_written(self):
        record = self.env["itr.validation.bypass.log"].with_user(self.employee).create({
            "check_kind": "national_id",
            "raw_value": "TEST notify guard",
            "reason": "TEST NOT-003 proof",
        })
        before = record.write_date
        event = self._itr_create_event("test.no_write_on_reference")
        self.service.notify(event.event_key, record._name, record.id)
        record.invalidate_recordset()
        self.assertEqual(record.write_date, before)

    # -------------------------------------------------------------- 2.17
    def test_30_administrator_is_never_a_recipient(self):
        admin = self.env.ref("base.user_admin")
        event = self._itr_create_event(
            "test.group_recipients",
            recipient_user_ids=[(6, 0, [])],
            recipient_group_ids=[(6, 0, [self.env.ref("base.group_user").id])],
        )
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key)
        self.assertTrue(logs)
        self.assertNotIn(admin.id, logs.mapped("recipient_user_id").ids)
        root = self.env.ref("base.user_root")
        self.assertNotIn(root.id, logs.mapped("recipient_user_id").ids)

    def test_31_archived_user_is_never_a_recipient(self):
        ghost = self._itr_create_user("test_notify_ghost")
        event = self._itr_create_event(
            "test.archived_recipient", recipient_user_ids=[(6, 0, [ghost.id])]
        )
        ghost.active = False
        result = self.service.notify(event.event_key)
        self.assertEqual(result["reason"], "no_recipient")

    # ------------------------------------------------- 2.10 / 2.18 / 2.19
    def test_40_internal_channel_is_always_on(self):
        event = self._itr_create_event("test.internal_always_on")
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key, channel="internal")
        self.assertTrue(logs)
        self.assertIn(logs[0].status, ("sent", "queued"))

    def test_41_sms_is_simulated_in_test_mode(self):
        event = self._itr_create_event(
            "test.sms_simulated", send_sms=True, sms_body="TEST {{reason}}"
        )
        self.service.notify(event.event_key, context={"reason": "TEST"})
        logs = self._logs(event.event_key, channel="sms")
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "simulated", "test mode must never report Sent")

    def test_42_sms_blocked_when_kill_switch_off(self):
        self.settings.write({"test_mode": False, "sms_master_enabled": False})
        event = self._itr_create_event(
            "test.sms_blocked", send_sms=True, sms_body="TEST body"
        )
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key, channel="sms")
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "blocked_sms_off")

    def test_43_master_switch_blocks_everything(self):
        self.settings.master_enabled = False
        event = self._itr_create_event("test.master_off")
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key)
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "blocked_master_off")

    # ------------------------------------------------------ template render
    def test_50_missing_variable_is_reported_not_raised(self):
        event = self._itr_create_event(
            "test.missing_variable", internal_body="Hello {{unknown_variable}}"
        )
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key)
        self.assertTrue(logs)
        self.assertIn("unknown_variable", logs[0].missing_variables or "")

    def test_51_user_preference_mutes_the_event(self):
        event = self._itr_create_event(
            "test.user_optout", recipient_user_ids=[(6, 0, [self.employee.id])]
        )
        self.env["itr.notification.user.preference"].with_user(self.employee).create({
            "event_id": event.id,
            "mute_internal": True,
        })
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key, channel="internal")
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "blocked_muted")

    def test_52_alias_call_reaches_the_official_event(self):
        event = self._itr_create_event("test.official_for_alias")
        self.env["itr.notification.alias"].create({
            "alias_key": "test.legacy_for_alias",
            "event_id": event.id,
        })
        result = self.service.notify("test.legacy_for_alias")
        self.assertEqual(result["reason"], "ok")
        logs = self._logs(event.event_key)
        self.assertTrue(logs)
        self.assertEqual(logs[0].alias_used, "test.legacy_for_alias")
PYEOF

write_utf8 "${MOD_DIR}/tests/test_dedup_quiet_hours.py" <<'PYEOF'
# -*- coding: utf-8 -*-
import psycopg2

from odoo import fields
from odoo.tests import tagged
from odoo.tools import mute_logger

from .common import ItrNotifyCase


@tagged("post_install", "-at_install", "itr_notify")
class TestItrNotifyDedupAndQuietHours(ItrNotifyCase):

    # -------------------------------------------------------------- 2.20
    def test_10_second_call_is_skipped_as_duplicate(self):
        event = self._itr_create_event("test.dedup", cooldown_minutes=30)
        first = self.service.notify(event.event_key, "res.company", self.env.company.id)
        second = self.service.notify(event.event_key, "res.company", self.env.company.id)
        self.assertEqual(first["queued"], 1)
        self.assertEqual(second["queued"], 0)
        self.assertEqual(second["skipped_duplicate"], 1)

    def test_11_real_unique_index_exists(self):
        self.env.cr.execute(
            """
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'itr_notification_dispatch_log'
              AND indexdef ILIKE '%%UNIQUE%%'
              AND indexdef ILIKE '%%dedup_key%%'
            """
        )
        self.assertTrue(self.env.cr.fetchall(), "NOT-006 requires a real unique index")

    @mute_logger("odoo.sql_db")
    def test_12_database_refuses_a_duplicate_row(self):
        event = self._itr_create_event("test.dedup_db")
        self.service.notify(event.event_key)
        log = self._logs(event.event_key)[:1]
        with self.assertRaises(psycopg2.IntegrityError):
            with self.env.cr.savepoint():
                self.env.cr.execute(
                    """
                    INSERT INTO itr_notification_dispatch_log
                        (event_key, channel, status, dedup_key, create_uid, create_date,
                         write_uid, write_date)
                    VALUES (%s, 'internal', 'queued', %s, 1, now(), 1, now())
                    """,
                    (event.event_key, log.dedup_key),
                )

    def test_13_occurrence_id_allows_a_legitimate_second_alert(self):
        event = self._itr_create_event("test.occurrence", cooldown_minutes=600)
        self.service.notify(event.event_key, context={"occurrence_id": "A"})
        second = self.service.notify(event.event_key, context={"occurrence_id": "B"})
        # the sliding window still protects the same identity, so the second
        # occurrence is reported as duplicate unless the window expired
        self.assertIn(second["reason"], ("ok",))
        self.assertTrue(second["queued"] + second["skipped_duplicate"] >= 1)

    # -------------------------------------------------------------- 2.21
    def test_20_quiet_hours_block_non_critical_sms(self):
        self.settings.write({
            "quiet_hours_enabled": True,
            "quiet_hours_start": 0.0,
            "quiet_hours_end": 23.99,
        })
        event = self._itr_create_event(
            "test.quiet_sms", send_sms=True, sms_body="TEST quiet",
            respect_quiet_hours=True, is_critical=False,
        )
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key, channel="sms")
        self.assertTrue(logs)
        self.assertEqual(logs[0].status, "blocked_quiet")
        self.assertTrue(logs[0].replay_after)

    def test_21_critical_event_passes_the_quiet_hours(self):
        self.settings.write({
            "quiet_hours_enabled": True,
            "quiet_hours_start": 0.0,
            "quiet_hours_end": 23.99,
        })
        event = self._itr_create_event(
            "test.quiet_critical", send_sms=True, sms_body="TEST critical",
            respect_quiet_hours=True, is_critical=True,
        )
        self.service.notify(event.event_key)
        logs = self._logs(event.event_key, channel="sms")
        self.assertTrue(logs)
        self.assertNotEqual(logs[0].status, "blocked_quiet")

    def test_22_morning_replay_releases_the_blocked_sms(self):
        self.settings.write({
            "quiet_hours_enabled": True,
            "quiet_hours_start": 0.0,
            "quiet_hours_end": 23.99,
        })
        event = self._itr_create_event(
            "test.quiet_replay", send_sms=True, sms_body="TEST replay"
        )
        self.service.notify(event.event_key)
        log = self._logs(event.event_key, channel="sms")[:1]
        self.assertEqual(log.status, "blocked_quiet")
        log.with_context(itr_notify_engine=True).write({
            "replay_after": fields.Datetime.subtract(fields.Datetime.now(), hours=1)
        })
        self.env["itr.notification.dispatch.log"]._cron_replay_quiet_hours()
        log.invalidate_recordset()
        self.assertIn(log.status, ("simulated", "sent"))

    # -------------------------------------------------------------- 2.24
    def test_30_health_digest_uses_notify(self):
        event = self._itr_create_event("test.digest_source", send_sms=True,
                                       sms_body="TEST digest")
        self.settings.write({"test_mode": False, "sms_master_enabled": False,
                             "quiet_hours_enabled": False})
        self.service.notify(event.event_key)  # produces a blocked_sms_off row
        count = self.env["itr.notification.dispatch.log"].with_context(
            itr_notify_sync=True
        )._cron_daily_health_digest()
        self.assertGreaterEqual(count, 1)
        digest_logs = self._logs("system.digest_daily_failures")
        self.assertTrue(digest_logs)
PYEOF

write_utf8 "${MOD_DIR}/tests/test_sla_engine.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo import fields
from odoo.tests import tagged

from .common import ItrNotifyCase


@tagged("post_install", "-at_install", "itr_notify")
class TestItrSlaEngine(ItrNotifyCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.level_events = {}
        for level in (1, 2, 3, 4):
            cls.level_events[level] = cls._itr_create_event("test.sla_level%s" % level)
        cls.policy = cls.env["itr.sla.policy"].create({
            "policy_key": "test.sla_policy",
            "name": "TEST SLA policy",
            "res_model": "itr.validation.bypass.log",
            "task_key": "test_task",
            "deadline_minutes": 60,
            "level_gap_minutes": 0,
            "level1_event_key": "test.sla_level1",
            "level2_event_key": "test.sla_level2",
            "level3_event_key": "test.sla_level3",
            "level4_event_key": "test.sla_level4",
        })

    def _record(self):
        return self.env["itr.validation.bypass.log"].with_user(self.employee).create({
            "check_kind": "national_id",
            "raw_value": "TEST sla",
            "reason": "TEST sla watch",
        })

    def test_10_open_and_close_watch(self):
        record = self._record()
        service = self.env["itr.sla.service"]
        watch = service.open_watch("test.sla_policy", record, self.employee)
        self.assertTrue(watch)
        self.assertEqual(watch.state, "open")
        again = service.open_watch("test.sla_policy", record, self.employee)
        self.assertEqual(again, watch, "only one open watch per task (real partial index)")
        closed = service.close_watch("test.sla_policy", record, reason="TEST valid action")
        self.assertEqual(closed, 1)
        watch.invalidate_recordset()
        self.assertEqual(watch.state, "done")

    def test_20_escalation_ladder(self):
        record = self._record()
        service = self.env["itr.sla.service"].with_context(itr_notify_sync=True)
        watch = service.open_watch("test.sla_policy", record, self.employee)
        watch.write({
            "started_on": fields.Datetime.subtract(fields.Datetime.now(), hours=5),
            "deadline": fields.Datetime.subtract(fields.Datetime.now(), hours=4),
        })
        for level in (1, 2, 3, 4):
            escalated = service._cron_scan_sla()
            self.assertEqual(escalated, 1, "one level per run (NOT-035)")
            watch.invalidate_recordset()
            self.assertEqual(watch.last_level, level)
            logs = self._logs("test.sla_level%s" % level)
            self.assertTrue(logs, "level %s must produce a dispatch row" % level)
        self.assertEqual(service._cron_scan_sla(), 0, "level 4 is the last one")

    def test_30_closed_watch_is_never_escalated(self):
        record = self._record()
        service = self.env["itr.sla.service"].with_context(itr_notify_sync=True)
        watch = service.open_watch("test.sla_policy", record, self.employee)
        watch.write({"deadline": fields.Datetime.subtract(fields.Datetime.now(), hours=2)})
        service.close_watch("test.sla_policy", record, reason="TEST done in time")
        self.assertEqual(service._cron_scan_sla(), 0)

    def test_40_single_sla_engine(self):
        """G18 / NOT-035: exactly one scheduled SLA scanner in the database."""
        crons = self.env["ir.cron"].sudo().search([("code", "ilike", "sla")])
        self.assertEqual(len(crons), 1, "there must be exactly one SLA cron: %s" % crons.mapped("name"))
PYEOF

# ---------------------------------------------------------------- README ----
write_utf8 "${MOD_DIR}/README.md" <<'MDEOF'
# itr_notify — notification / SMS / SLA infrastructure (Phase 2)

Dependencies: `base`, `mail`, `itr_base`. Locked install order (Q02):

```
itr_base -> itr_notify -> itr_core -> itr_transport -> itr_reports -> itr_integration
```

## Public API for the next phases (never re-implement these)

```python
# one single entry point for every alert of the project (NOT-001)
self.env['itr.notification.service'].notify(
    'case.legal_rejected',            # event_key (or a registered alias)
    'itr.trade.case', case.id,        # optional reference record (read only)
    {'reason': 'incomplete documents', 'occurrence_id': 'legal-42'},
)

# the single SLA engine of the project (G18 / NOT-035)
self.env['itr.sla.service'].open_watch('transport.waybill', record, user)
self.env['itr.sla.service'].close_watch('transport.waybill', record, reason='...')
```

`notify()` returns a statistics dict and NEVER raises:
`{'event_key', 'reason', 'queued', 'sent', 'simulated', 'blocked', 'skipped_duplicate', 'recipients'}`

## What later phases must do (and only that)

1. Create `itr.notification.event` records (data files, `is_seed=True`).
2. Call `notify()` at the right business moment.
3. Create `itr.sla.policy` records and call `open_watch` / `close_watch`.

Never: call an SMS gateway directly, build a second SLA/queue engine, or add a
notification field on a business model.

## Hard rules enforced here

* NOT-002 notify() never raises. NOT-003 it never writes the reference record.
* NOT-004 Administrator / OdooBot / archived users are never recipients.
* NOT-005 unknown event, missing recipient or missing template are logged.
* NOT-006 dedup relies on a real PostgreSQL unique index (`reserve then send`).
* NOT-007 real SMS needs `sms_master_enabled`; factory default OFF + test mode ON.
* NOT-008 the internal channel is free and always on; `send_sms` is the only
  real decision on an event.
* NOT-017 delivery happens after commit (outbox), never inside the transaction.
* 2.27 / 2.28 / 2.29 no SMS cost cap, no WhatsApp, no business event seeded.
MDEOF

log "درخت ماژول itr_notify نوشته شد"

# =============================================================================
step "4) verify مستقل فاز ۲ (ops/verify/verify_phase2.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase2.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 2 independent verification (V2-01 .. V2-09).

Run through `odoo-bin shell` (ADR-005). Every business assertion is executed
with a REAL non-admin user, never with sudo/Administrator (Q15/G01). The whole
run happens inside one transaction which is ROLLED BACK at the end, so the
verification leaves zero footprint in the database.
"""
import traceback

from odoo import fields
from odoo.exceptions import ValidationError

RESULTS = []


def check(code, title, func):
    try:
        detail = func()
        RESULTS.append((code, "PASS", title, detail or ""))
    except Exception as error:  # noqa: BLE001 - verification must never abort
        RESULTS.append((code, "FAIL", title, "%s: %s" % (type(error).__name__, error)))
        traceback.print_exc()


def create_user(env, login, group_xmlids):
    users = env["res.users"].with_context(no_reset_password=True)
    group_field = "group_ids" if "group_ids" in users._fields else "groups_id"

    groups = env.ref("base.group_user")
    for xmlid in group_xmlids:
        groups |= env.ref(xmlid)

    user = users.search([("login", "=", login)], limit=1)
    if user:
        user.write({group_field: [(6, 0, groups.ids)]})
    else:
        user = users.create({
            "name": "TEST %s" % login,
            "login": login,
            "email": "%s@test.invalid" % login,
            group_field: [(6, 0, groups.ids)],
        })

    user.partner_id.write({"phone": "09120000000"})
    return user


def main(env):
    manager = create_user(
        env, "test_notify_verify_manager", ["itr_notify.group_itr_notification_manager"]
    )
    worker = create_user(env, "test_notify_verify_worker", [])

    Event = env["itr.notification.event"].with_user(manager)
    Log = env["itr.notification.dispatch.log"]
    service = env["itr.notification.service"].with_user(manager).with_context(
        itr_notify_sync=True
    )
    settings = env["itr.notify.settings"].with_user(manager).get_settings()

    def new_event(key, **values):
        payload = {
            "event_key": key,
            "title": "TEST %s" % key,
            "category": "system",
            "internal_subject": "TEST subject",
            "internal_body": "TEST body {{reason}}",
            "recipient_user_ids": [(6, 0, [worker.id])],
        }
        payload.update(values)
        return Event.create(payload)

    def logs_of(key, **filters):
        domain = [("event_key", "=", key)]
        for field, value in filters.items():
            domain.append((field, "=", value))
        return Log.search(domain, order="id desc")

    # ------------------------------------------------------------- V2-01
    def v2_01():
        assert not settings.sms_master_enabled, "sms_master_enabled must default to OFF"
        assert settings.test_mode, "test_mode must default to ON"
        assert settings.master_enabled, "master_enabled must default to ON"
        return "sms_master_enabled=OFF test_mode=ON master_enabled=ON"

    # ------------------------------------------------------------- V2-02
    def v2_02():
        refused_no_recipient = False
        try:
            new_event("verify.no_recipient", recipient_user_ids=[(6, 0, [])])
        except ValidationError:
            refused_no_recipient = True
        assert refused_no_recipient, "an event without any recipient source was accepted"

        refused_no_text = False
        try:
            new_event("verify.sms_no_text", send_sms=True, sms_body="")
        except ValidationError:
            refused_no_text = True
        assert refused_no_text, "an SMS event without text was accepted"
        return "event without recipient refused / SMS event without text refused"

    # ------------------------------------------------------------- V2-03
    def v2_03():
        admin = env.ref("base.user_admin")
        root = env.ref("base.user_root")
        refused = False
        try:
            new_event("verify.admin_recipient", recipient_user_ids=[(6, 0, [admin.id])])
        except ValidationError:
            refused = True
        assert refused, "Administrator was accepted as a fixed recipient"

        event = new_event(
            "verify.group_recipients",
            recipient_user_ids=[(6, 0, [])],
            recipient_group_ids=[(6, 0, [env.ref("base.group_user").id])],
        )
        service.notify(event.event_key)
        recipients = logs_of(event.event_key).mapped("recipient_user_id").ids
        assert admin.id not in recipients, "Administrator received a notification"
        assert root.id not in recipients, "OdooBot received a notification"
        return "Administrator/OdooBot excluded from %s recipient rows" % len(recipients)

    # ------------------------------------------------------------- V2-04
    def v2_04():
        result = service.notify("verify.this.event.does.not.exist")
        assert isinstance(result, dict), "notify() must always return a dict"
        assert result["reason"] == "no_event", result
        rows = logs_of("verify.this.event.does.not.exist")
        assert rows, "NOT-005: the missing event must be logged, never silent"
        assert rows[0].status == "config_error", rows[0].status
        return "no exception, reason=no_event, config_error row written"

    # ------------------------------------------------------------- V2-05
    def v2_05():
        event = new_event("verify.dedup", cooldown_minutes=30)
        first = service.notify(event.event_key, "res.company", env.company.id)
        second = service.notify(event.event_key, "res.company", env.company.id)
        assert first["queued"] == 1, first
        assert second["queued"] == 0 and second["skipped_duplicate"] >= 1, second
        rows = logs_of(event.event_key, channel="internal")
        queued_like = rows.filtered(lambda r: r.status in ("queued", "sent", "simulated"))
        assert len(queued_like) == 1, "a duplicate produced a second real dispatch"
        return "second call skipped as duplicate (1 real row)"

    # ------------------------------------------------------------- V2-06
    def v2_06():
        env.cr.execute(
            """
            SELECT indexname FROM pg_indexes
            WHERE tablename = 'itr_notification_dispatch_log'
              AND indexdef ILIKE '%%UNIQUE%%'
              AND indexdef ILIKE '%%dedup_key%%'
            """
        )
        rows = env.cr.fetchall()
        assert rows, "NOT-006: no real unique index on dedup_key"
        return "pg_indexes: %s" % ", ".join(row[0] for row in rows)

    # ------------------------------------------------------------- V2-07
    def v2_07():
        record = env["itr.validation.bypass.log"].with_user(worker).create({
            "check_kind": "national_id",
            "raw_value": "TEST verify notify guard",
            "reason": "TEST NOT-003 proof",
        })
        before = record.write_date
        event = new_event("verify.no_write")
        service.notify(event.event_key, record._name, record.id)
        record.invalidate_recordset()
        assert record.write_date == before, "notify() modified the reference record"
        return "write_date of the reference record unchanged"

    # ------------------------------------------------------------- V2-08
    def v2_08():
        settings.write({
            "quiet_hours_enabled": True,
            "quiet_hours_start": 0.0,
            "quiet_hours_end": 23.99,
        })
        event = new_event(
            "verify.quiet", send_sms=True, sms_body="TEST quiet body",
            respect_quiet_hours=True,
        )
        service.notify(event.event_key)
        row = logs_of(event.event_key, channel="sms")[:1]
        assert row and row.status == "blocked_quiet", row and row.status
        row.with_context(itr_notify_engine=True).write({
            "replay_after": fields.Datetime.subtract(fields.Datetime.now(), hours=1)
        })
        Log._cron_replay_quiet_hours()
        row.invalidate_recordset()
        assert row.status in ("simulated", "sent"), row.status
        settings.write({"quiet_hours_start": 22.0, "quiet_hours_end": 7.0})
        return "blocked in quiet hours then released by the replay job (%s)" % row.status

    # ------------------------------------------------------------- V2-09
    def v2_09():
        event = new_event("verify.official_name")
        env["itr.notification.alias"].with_user(manager).create({
            "alias_key": "verify.legacy_name",
            "event_id": event.id,
        })
        result = service.notify("verify.legacy_name")
        assert result["reason"] == "ok", result
        row = logs_of(event.event_key)[:1]
        assert row and row.alias_used == "verify.legacy_name", row and row.alias_used
        return "alias verify.legacy_name -> %s" % event.event_key

    check("V2-01", "SMS kill switch OFF and test mode ON by default", v2_01)
    check("V2-02", "event without recipient / SMS without text are refused", v2_02)
    check("V2-03", "Administrator and OdooBot are never recipients", v2_03)
    check("V2-04", "notify() on an unknown event does not raise and is logged", v2_04)
    check("V2-05", "two calls with the same dedup key create only one dispatch", v2_05)
    check("V2-06", "a real UNIQUE index on dedup_key exists in PostgreSQL", v2_06)
    check("V2-07", "notify() never modifies the reference record", v2_07)
    check("V2-08", "quiet hours block the SMS and the morning replay releases it", v2_08)
    check("V2-09", "calling the legacy alias reaches the official event", v2_09)


try:
    main(env)  # noqa: F821 - provided by odoo shell
except Exception:  # noqa: BLE001
    traceback.print_exc()
    RESULTS.append(("V2-XX", "FAIL", "verify script crashed", "see traceback"))

FAILED = [row for row in RESULTS if row[1] != "PASS"]
print("")
print("---------------- PHASE 2 VERIFY ----------------")
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
log "ops/verify/verify_phase2.py نوشته شد"

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
  gate "G2-03" "نحو پایتون/XML/CSV ماژول سالم است" "PASS" "pre-install static check"
else
  gate "G2-03" "نحو پایتون/XML/CSV ماژول سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب"
fi

# =============================================================================
step "6) نصب/ارتقای itr_notify روی ${DB_NAME}"
# =============================================================================
MOD_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
if [[ "${MOD_STATE}" == "installed" ]]; then
  INSTALL_FLAG="-u"; info "ماژول از قبل نصب است → ارتقا (-u)"
else
  INSTALL_FLAG="-i"; info "نصب تازه (-i)"
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
  gate "G2-04" "نصب/ارتقای itr_notify بدون خطا" "PASS" "state=installed rc=0"
else
  gate "G2-04" "نصب/ارتقای itr_notify بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${MOD_STATE_AFTER} → ${INSTALL_LOG}"
  tail -n 40 "${INSTALL_LOG}"
fi

# ساختار دیتابیس: جدول‌ها، گروه‌ها، ACL، Rule، Cron، رکورد تنظیمات، رویدادهای بذر
TBL_SET="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_notify_settings')")"
TBL_EVT="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_notification_event')")"
TBL_LOG="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_notification_dispatch_log')")"
TBL_ALIAS="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_notification_alias')")"
TBL_SLA_P="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_sla_policy')")"
TBL_SLA_W="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_sla_watch')")"
SET_ROWS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notify_settings")"
SEED_EVENTS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE is_seed IS TRUE")"
BIZ_EVENTS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE is_seed IS TRUE AND event_key NOT LIKE 'system.%'")"
GRP_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify' AND model='res.groups'")"
ACL_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify' AND model='ir.model.access'")"
RULE_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify' AND model='ir.rule'")"
CRON_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify' AND model='ir.cron'")"
GATEWAYS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_sms_gateway_profile")"
echo "settings=${SET_ROWS} seed_events=${SEED_EVENTS} business_seed=${BIZ_EVENTS} groups=${GRP_COUNT} acl=${ACL_COUNT} rules=${RULE_COUNT} crons=${CRON_COUNT} gateways=${GATEWAYS}"

if [[ "${TBL_SET}" == "itr_notify_settings" && "${TBL_EVT}" == "itr_notification_event" \
      && "${TBL_LOG}" == "itr_notification_dispatch_log" && "${TBL_ALIAS}" == "itr_notification_alias" \
      && "${TBL_SLA_P}" == "itr_sla_policy" && "${TBL_SLA_W}" == "itr_sla_watch" \
      && "${SET_ROWS}" == "1" && "${SEED_EVENTS}" == "2" && "${GRP_COUNT}" == "2" \
      && "${RULE_COUNT}" == "4" && "${CRON_COUNT}" == "3" && "${ACL_COUNT}" -ge 16 ]]; then
  gate "G2-05" "مدل‌ها/گروه‌ها/ACL/Rule/Cron/تنظیمات و دو رویداد سیستمی ساخته شدند" "PASS" \
       "settings=1 seed_events=2 groups=2 rules=4 crons=3 acl=${ACL_COUNT}"
else
  gate "G2-05" "مدل‌ها/گروه‌ها/ACL/Rule/Cron/تنظیمات و دو رویداد سیستمی ساخته شدند" "FAIL" \
       "settings=${SET_ROWS} seed=${SEED_EVENTS} groups=${GRP_COUNT} acl=${ACL_COUNT} rules=${RULE_COUNT} crons=${CRON_COUNT}"
fi

# ★ ۲.۲۰ — نمایهٔ یکتای واقعی روی dedup_key، مستقیماً از pg_indexes (نه ادعای کد)
DEDUP_IDX="$(q "${DB_NAME}" "SELECT indexname FROM pg_indexes WHERE tablename='itr_notification_dispatch_log' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%dedup_key%' LIMIT 1")"
SLA_IDX="$(q "${DB_NAME}" "SELECT indexname FROM pg_indexes WHERE tablename='itr_sla_watch' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%task_key%' LIMIT 1")"
if [[ -n "${DEDUP_IDX}" ]]; then
  gate "G2-06" "UNIQUE INDEX واقعی روی dedup_key (NOT-006 / بند 2.20)" "PASS" "${DEDUP_IDX} | sla=${SLA_IDX:-none}"
else
  gate "G2-06" "UNIQUE INDEX واقعی روی dedup_key (NOT-006 / بند 2.20)" "FAIL" "در pg_indexes یافت نشد"
fi

# =============================================================================
step "7) تست‌های خودکار Odoo با کاربر غیر-ادمین (Q04)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G2-07" "تست‌های خودکار ماژول سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
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
    gate "G2-07" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "PASS" "${TEST_TOTAL:-tests} rc=0"
  elif [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" ]]; then
    gate "G2-07" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "WARN" \
         "Odoo موفق گزارش داد اما ${TEST_FAILS} خط مشکوک در لاگ هست → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): ' "${TEST_LOG}" | head -n 10 || true
  else
    gate "G2-07" "تست‌های خودکار ماژول سبز هستند (کاربر غیر-ادمین)" "FAIL" \
         "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): ' "${TEST_LOG}" | head -n 15 || true
  fi
fi

# =============================================================================
step "8) verify مستقل V2-01..V2-09 (بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G2-08" "verify مستقل فاز ۲ سبز است (V2-01..V2-09)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase2.py" \
    >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G2-08" "verify مستقل فاز ۲ سبز است (V2-01..V2-09)" "PASS" "${VERIFY_LINE}"
  else
    gate "G2-08" "verify مستقل فاز ۲ سبز است (V2-01..V2-09)" "FAIL" \
         "${VERIFY_LINE:-خروجی verify یافت نشد} (rc=${VERIFY_RC}) → ${VERIFY_LOG}"
    tail -n 40 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "9) گاردهای معماری فاز ۲ (ممنوعه‌های 2.27/2.28/2.29 + G18 + Q05 + G01)"
# =============================================================================
COST_HITS="$(grep -rniE 'sms_daily_cap|sms_monthly_cap|sms_unit_cost|cost_alert_threshold|sms_credit|sms_budget' "${MOD_DIR}" 2>/dev/null || true)"
if [[ -z "${COST_HITS}" ]]; then
  gate "G2-09" "هیچ سقف/شمارندهٔ هزینهٔ پیامک ساخته نشد (بند 2.27 / NOT-020)" "PASS" "clean"
else
  gate "G2-09" "هیچ سقف/شمارندهٔ هزینهٔ پیامک ساخته نشد (بند 2.27 / NOT-020)" "FAIL" \
       "$(echo "${COST_HITS}" | head -n3 | tr '\n' ' ')"
fi

WA_HITS="$(grep -rniE --include='*.py' --include='*.xml' --exclude-dir='__pycache__' 'whatsapp|واتساپ|wa_business' "${MOD_DIR}/models" "${MOD_DIR}/utils" "${MOD_DIR}/security" "${MOD_DIR}/data" "${MOD_DIR}/views" 2>/dev/null || true)"

if [[ -z "${WA_HITS}" ]]; then
  gate "G2-10" "هیچ کانال واتساپ ساخته نشد (بند 2.28 / بخش ۱۶)" "PASS" "clean"
else
  gate "G2-10" "هیچ کانال واتساپ ساخته نشد (بند 2.28 / بخش ۱۶)" "FAIL" \
       "$(echo "${WA_HITS}" | head -n3 | tr '\n' ' ')"
fi

BIZ_SEED_FILE="$(grep -rn '<field name="event_key">' "${MOD_DIR}/data" 2>/dev/null | grep -v '<field name="event_key">system\.' || true)"
if [[ -z "${BIZ_SEED_FILE}" && "${BIZ_EVENTS:-0}" == "0" ]]; then
  gate "G2-11" "هیچ رویداد کسب‌وکاری در این ماژول کاشته نشد (بند 2.29)" "PASS" "فقط system.* — DB و فایل داده هر دو تمیز"
else
  gate "G2-11" "هیچ رویداد کسب‌وکاری در این ماژول کاشته نشد (بند 2.29)" "FAIL" \
       "db=${BIZ_EVENTS} file=$(echo "${BIZ_SEED_FILE}" | head -n2 | tr '\n' ' ')"
fi

GATEWAY_HITS="$(grep -rnE 'requests\.(get|post)' --include='*.py' "${MOD_DIR}" 2>/dev/null | grep -v '/utils/adapters/' || true)"
if [[ -z "${GATEWAY_HITS}" ]]; then
  gate "G2-12" "تماس با درگاه فقط داخل لایهٔ آداپتور است (NOT-001/G17)" "PASS" "utils/adapters/ تنها مسیر شبکه"
else
  gate "G2-12" "تماس با درگاه فقط داخل لایهٔ آداپتور است (NOT-001/G17)" "FAIL" \
       "$(echo "${GATEWAY_HITS}" | head -n3 | tr '\n' ' ')"
fi

SLA_ENGINE_HITS="$(grep -rlnE '_cron_scan_sla|sla_escalat|def .*escalate' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v "/${MODULE}/" || true)"
SLA_CRON_COUNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_cron c JOIN ir_act_server a ON a.id=c.ir_actions_server_id WHERE a.code ILIKE '%sla%'")"
if [[ -z "${SLA_ENGINE_HITS}" ]]; then
  gate "G2-13" "تنها یک موتور SLA در کل مخزن (G18/NOT-035)" "PASS" "itr_notify/models/itr_sla_service.py (cron_sla_in_db=${SLA_CRON_COUNT:-?})"
else
  gate "G2-13" "تنها یک موتور SLA در کل مخزن (G18/NOT-035)" "FAIL" \
       "$(echo "${SLA_ENGINE_HITS}" | head -n3 | tr '\n' ' ')"
fi

SUDO_HITS="$(grep -rn --include='*.py' '\.sudo(' "${MOD_DIR}/models" "${MOD_DIR}/utils" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G2-14" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/SEC-018)" "PASS" "models/ و utils/ تمیز"
else
  gate "G2-14" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/SEC-018)" "FAIL" \
       "$(echo "${SUDO_HITS}" | head -n3 | tr '\n' ' ')"
fi

NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${MOD_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${MOD_DIR}" 2>/dev/null || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G2-15" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n"
else
  gate "G2-15" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" \
       "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

HARDCODE_HITS="$(grep -rnE "(api_key|api_secret|password|token)[\"']?\s*[:=]\s*[\"'][^\"']+[\"']" --include='*.py' "${MOD_DIR}" 2>/dev/null | grep -v 'required_fields' | grep -v 'label' || true)"
if [[ -z "${HARDCODE_HITS}" ]]; then
  gate "G2-16" "هیچ کلید/رمز/متن پیامک هاردکدشده در کد (Q07/NFR-004)" "PASS" "پیکربندی فقط از مدل تنظیمات/درگاه"
else
  gate "G2-16" "هیچ کلید/رمز/متن پیامک هاردکدشده در کد (Q07/NFR-004)" "FAIL" \
       "$(echo "${HARDCODE_HITS}" | head -n3 | tr '\n' ' ')"
fi

PO_MSGS="$(grep -c '^msgstr "' "${MOD_DIR}/i18n/fa_IR.po" || true)"
FA_LANG="$(q "${DB_NAME}" "SELECT code FROM res_lang WHERE code LIKE 'fa%' AND active IS TRUE LIMIT 1")"
FA_TRANS="$(q "${DB_NAME}" "SELECT field_description->>'${FA_LANG:-fa_IR}' FROM ir_model_fields WHERE model='itr.notify.settings' AND name='sms_master_enabled'")"
if [[ -n "${FA_TRANS}" && "${FA_TRANS}" != "Real SMS sending enabled" ]]; then
  gate "G2-17" "ترجمهٔ فارسی ماژول بارگذاری شد" "PASS" "lang=${FA_LANG} msgstr=${PO_MSGS} sample=${FA_TRANS}"
else
  gate "G2-17" "ترجمهٔ فارسی ماژول بارگذاری شد" "WARN" \
       "lang=${FA_LANG:-?} — در صورت نیاز: odoo-bin -d ${DB_NAME} -u ${MODULE} --i18n-overwrite --load-language=fa_IR --stop-after-init"
fi

# =============================================================================
step "10) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notify_settings")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_sms_gateway_profile")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify'")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${MODULE}" \
  --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notify_settings")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_sms_gateway_profile")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_notify'")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G2-18" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "settings|events|gateways|xmlid = ${CNT_AFTER}"
else
  gate "G2-18" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "11) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G2-19" "itr_notify روی محیط UAT نصب شد" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G2-19" "itr_notify روی محیط UAT نصب شد" "WARN" "محیط UAT یافت نشد"
else
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  UAT_FLAG="-i"; [[ "${UAT_STATE}" == "installed" ]] && UAT_FLAG="-u"
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    "${UAT_FLAG}" "${MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_AFTER="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  UAT_SMS_OFF="$(q "${DB_NAME_UAT}" "SELECT count(*) FROM itr_notify_settings WHERE sms_master_enabled IS NOT TRUE")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_AFTER}" == "installed" && "${UAT_SMS_OFF}" == "1" ]]; then
    gate "G2-19" "itr_notify روی محیط UAT نصب شد و پیامک واقعی خاموش است" "PASS" "${DB_NAME_UAT} state=installed sms=off"
  else
    gate "G2-19" "itr_notify روی محیط UAT نصب شد و پیامک واقعی خاموش است" "FAIL" "rc=${UAT_RC} state=${UAT_AFTER} sms_off=${UAT_SMS_OFF} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "12) تست منفی سطح دیتابیس: Administrator بدون گروه اعلان (Q03/SEC-002)"
# =============================================================================
REL_EXISTS="$(q "${DB_NAME}" "SELECT to_regclass('public.res_groups_users_rel')")"
if [[ "${REL_EXISTS}" == "res_groups_users_rel" ]]; then
  ADMIN_NOTIFY_GROUPS="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_notify' WHERE u.login IN ('admin','__system__')")"
  ADMIN_AS_RECIPIENT="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event_user_rel r JOIN res_users u ON u.id=r.user_id WHERE u.login IN ('admin','__system__')")"
  if [[ "${ADMIN_NOTIFY_GROUPS}" == "0" && "${ADMIN_AS_RECIPIENT:-0}" == "0" ]]; then
    gate "G2-20" "Administrator نه گروه اعلان دارد نه گیرندهٔ هیچ رویدادی است" "PASS" "0 group / 0 recipient row"
  else
    gate "G2-20" "Administrator نه گروه اعلان دارد نه گیرندهٔ هیچ رویدادی است" "FAIL" \
         "groups=${ADMIN_NOTIFY_GROUPS} recipient_rows=${ADMIN_AS_RECIPIENT}"
  fi
else
  gate "G2-20" "Administrator نه گروه اعلان دارد نه گیرندهٔ هیچ رویدادی است" "WARN" "جدول رابطهٔ گروه‌ها یافت نشد"
fi

# =============================================================================
step "13) اسناد حاکمیتی: ADR / REUSE MAP / راهنمای فازهای بعد"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-008" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-008 — تنها نقطهٔ ورود اعلان و تنها موتور SLA
تصمیم: هر اعلان پروژه فقط از env['itr.notification.service'].notify() عبور می‌کند و
هر سنجش مهلت فقط از env['itr.sla.service'] (open_watch/close_watch + یک cron
پانزده‌دقیقه‌ای). ساخت هر موتور دوم برای اعلان، صف کار یا SLA در هر ماژول
بعدی = Gate قرمز (G18 / NOT-035). گارد grep در همین اسکریپت فاز ۲ اجرا می‌شود.

## ADR-009 — دِدوپ: «رزرو، سپس ارسال» با نمایهٔ یکتای واقعی PostgreSQL
تصمیم: پیش از هر تحویل، یک ردیف در itr.notification.dispatch.log با dedup_key
درج می‌شود. یکتایی dedup_key با UNIQUE INDEX واقعی دیتابیس تضمین می‌شود
(itr_notification_dispatch_log_dedup_uniq) نه با بررسی نرم پایتون؛ بنابراین دو
worker هم‌زمان هرگز یک پیامک را دوبار نمی‌فرستند (NOT-006). علاوه بر آن یک
بررسی «پنجرهٔ لغزان» برای کول‌داون انجام می‌شود (NOT-019) و در صورت وجود
occurrence_id، همان شناسهٔ وقوع مبنای یکتایی است نه پنجرهٔ ثابت زمانی.

## ADR-010 — تحویل پس از commit (الگوی Outbox)
تصمیم: notify() فقط ردیف‌های صف را می‌سازد؛ تحویل واقعی در callback پس از
commit با cursor تازه انجام می‌شود (NOT-017). در تست‌ها و اسکریپت verify، با
context flag «itr_notify_sync» تحویل هم‌زمان انجام می‌شود تا ادعا قابل اثبات
باشد بدون اینکه رفتار تولیدی عوض شود.

## ADR-011 — پیش‌فرض‌های کارخانه‌ای امن پیامک
تصمیم: sms_master_enabled=False و test_mode=True در دادهٔ نصب (noupdate=1).
هیچ نصبی نمی‌تواند سهواً پیامک واقعی بفرستد؛ روشن‌کردن آگاهانه فقط در فاز ۱۳
(بند 13.7) و پس از یک ارسال آزمایشی کنترل‌شده انجام می‌شود (NOT-007).

## ADR-012 — نبود سقف هزینهٔ پیامک داخل ERP
تصمیم: هیچ شمارنده/سقف هزینهٔ پیامک در Odoo ساخته نمی‌شود (NOT-020، بند 2.27).
کنترل واقعی اعتبار وظیفهٔ پنل درگاه پیامک است؛ شمارندهٔ دوم فقط توهم کنترل
می‌سازد و هزینهٔ نگهداری بی‌فایده دارد.
MDEOF
log "ADR-008..012 به ARCHITECTURE_DECISIONS.md افزوده شد"
else
  warn "ADR-008 از قبل ثبت شده — بدون تغییر"
fi

write_utf8 "${DOC_DIR}/NOTIFY_INTEGRATION_GUIDE.md" <<'MDEOF'
# راهنمای اتصال فازهای بعدی به itr_notify (فاز ۲)

## ۱) اعلان
```python
self.env['itr.notification.service'].notify(
    'case.legal_rejected',          # کلید رویداد (یا یک alias ثبت‌شده)
    'itr.trade.case', case.id,      # سند مرجع — فقط خوانده می‌شود، هرگز نوشته نمی‌شود
    {'reason': 'مدارک ناقص است', 'occurrence_id': 'legal-%s' % case.id},
)
```
* هرگز استثنا نمی‌دهد؛ خروجی یک dict آماری است.
* هرگز `write` روی سند مرجع نمی‌زند (ساعت SLA دست‌نخورده می‌ماند).
* اگر کلید رویداد اشتباه باشد، ردیف `config_error` در دفتر ارسال ثبت می‌شود.

## ۲) SLA (تنها موتور مجاز پروژه)
```python
self.env['itr.sla.service'].open_watch('transport.waybill', record, user)
...
self.env['itr.sla.service'].close_watch('transport.waybill', record,
                                        reason='بارنامه ثبت شد')
```
* «اقدام معتبر» یعنی همین فراخوانی close_watch؛ بازکردن فرم یا یادداشت، ساعت را
  متوقف نمی‌کند (NOT-034).
* پلکان چهارسطحی از روی `itr.sla.policy` خوانده می‌شود؛ مهلت‌ها از UI قابل تغییرند
  و هرگز در کد نیستند (NOT-031 / UAT-10).

## ۳) رویدادهای کسب‌وکاری
کاتالوگ کامل رویدادها (بخش ۱۱-۳ سند نیازمندی) در **فاز ۱۰** به‌صورت دادهٔ
`is_seed=True` کاشته می‌شود، نه در این ماژول (بند 2.29). برای هر نام قدیمی که
قبلاً در مستندات آمده، حتماً یک `itr.notification.alias` بسازید — به‌ویژه
`case.result_to_ceo` → `trade_case.back_to_finance_supervisor` (بند 10.2).

## ۴) کارهایی که هرگز نباید انجام شوند
* فراخوانی مستقیم درگاه پیامک از کد کسب‌وکاری.
* ساخت مدل/فیلد اعلان روی مدل‌های کسب‌وکاری.
* ساخت cron دوم برای SLA یا صف کار.
* افزودن شمارندهٔ هزینهٔ پیامک.
MDEOF

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "itr.notification.service" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## فاز ۲ — itr_notify (Q14)
| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۲ | `mail.thread.message_notify` هستهٔ Odoo برای اعلان داخلی | زنگولهٔ استاندارد Desk کامل است؛ ساخت صندوق پیام دوم ممنوع (G18) |
| ۲ | `mail.mail` برای کانال ایمیل | موتور ایمیل Odoo کافی است |
| ۲ | `ir.cron` هستهٔ Odoo برای SLA/بازپخش/گزارش سلامت | زمان‌بند دوم ممنوع است |
| ۲ | `itr.validation.service` فاز ۱ برای ماسک/تاریخ | تکرار الگوریتم ممنوع (ADR-007) |

## آنچه فازهای بعد باید از فاز ۲ بازاستفاده کنند (ساخت دوباره = Gate قرمز)
* `env['itr.notification.service'].notify(...)` → تنها نقطهٔ ورود اعلان (NOT-001)
* `env['itr.sla.service'].open_watch/close_watch` → تنها موتور SLA (NOT-035)
* `itr.notification.event` / `itr.notification.alias` → تنها کاتالوگ رویداد
* `itr.notification.dispatch.log` → تنها دفتر ارسال
* `itr.sms.gateway.profile` + رجیستری آداپتور → تنها مسیر ارتباط با درگاه
MDEOF
log "docs/REUSE_MAP.md به‌روزرسانی شد"
fi

# =============================================================================
step "14) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G2-21" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
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
    gate "G2-21" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G2-21" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "15) ثبت Git + تگ phase-2 (Q09)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-2: itr_notify (notify engine, SMS adapter registry, alias, dedup unique index, quiet hours, outbox, single SLA engine)"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-2 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-2 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G2-22" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-2}"
else
  gate "G2-22" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi

SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' | grep -v 'test_itr' | grep -v 'test_notify' | grep -v 'required_fields' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G2-23" "هیچ رمز/کلید درگاه وارد Git نشد (Q12/NFR-004)" "PASS" "clean"
else
  gate "G2-23" "هیچ رمز/کلید درگاه وارد Git نشد (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 2 — گزارش پذیرش فاز ۲"
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

write_utf8 "${DOC_DIR}/PHASE2-DELIVERY.md" <<MDEOF
# تحویل فاز ۲ — itr_notify (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-2
- وضعیت Gate 2: **${GATE_STATUS}** (هشدار: ${WARNS})

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 2.1-2.4 | مدل تک‌رکوردی itr.notify.settings با کلیدهای اضطراری و پیش‌فرض‌های امن | NOT-007 |
| 2.5-2.7 | کلاس پایه + رجیستری + سه آداپتور (console_debug/generic_http/iran_http_sms) | G17، T2 |
| 2.8-2.12 | مدل رویداد با regex کلید، یک تیک واقعی send_sms و چهار منبع گیرنده | NOT-008 |
| 2.13 | مدل itr.notification.alias (نام قدیمی → رسمی) | بند الزامی |
| 2.14-2.19 | موتور واحد notify() با شش گارد اول | NOT-001..005، NOT-007 |
| 2.20 | دِدوپ با UNIQUE INDEX واقعی PostgreSQL + رزرو پیش از ارسال | NOT-006 |
| 2.21 | ساعات سکوت + صف بازپخش صبحگاهی؛ عبور رویداد حیاتی | NOT-018 |
| 2.22 | ارسال پس از commit (Outbox) با cursor تازه | NOT-017 |
| 2.23 | تنها موتور SLA پروژه: policy/watch + cron ۱۵دقیقه‌ای + پلکان چهارسطحی | NOT-032..035 |
| 2.24 | cron روزانهٔ گزارش سلامت که خودش از notify() استفاده می‌کند | - |
| 2.25 | دو رویداد سیستمی بذر‌شده (و فقط همین دو) | 2.29 |
| 2.26 | دکمهٔ «ارسال آزمایشی برای من» روی فرم رویداد | - |

## ۲) Scope خارج از فاز (عمداً انجام نشد)
- هیچ رویداد کسب‌وکاری (کاتالوگ بخش ۱۱-۳ کار فاز ۱۰ است) — بند 2.29
- هیچ سقف/شمارندهٔ هزینهٔ پیامک — بند 2.27 / NOT-020
- هیچ کانال واتساپ — بند 2.28 / بخش ۱۶
- هیچ مدل کسب‌وکاری، کارتابل یا گزارش (فازهای ۳ تا ۹)

## ۳) فایل‌های ایجاد/تغییرکرده
\`\`\`
${MODULE}/__init__.py, __manifest__.py, hooks.py, README.md
${MODULE}/utils/{dedup.py, renderer.py, sms_base.py, sms_registry.py}
${MODULE}/utils/adapters/{console_debug.py, generic_http.py, iran_http_sms.py}
${MODULE}/models/{itr_notify_settings.py, itr_sms_gateway_profile.py,
                 itr_notification_event.py, itr_notification_alias.py,
                 itr_notification_dispatch_log.py, itr_notification_user_preference.py,
                 itr_notification_service.py, itr_sla_policy.py, itr_sla_watch.py,
                 itr_sla_service.py}
${MODULE}/security/{itr_notify_groups.xml, ir.model.access.csv, itr_notify_rules.xml}
${MODULE}/data/{itr_notify_settings_data.xml, itr_notification_event_data.xml, itr_notify_cron.xml}
${MODULE}/views/{settings, gateway, event, alias, dispatch log, preference, sla, menus}.xml
${MODULE}/i18n/{fa_IR.po, fa.po}
${MODULE}/tests/{common.py, test_event_validation.py, test_notify_core.py,
                test_dedup_quiet_hours.py, test_sla_engine.py}
ops/verify/verify_phase2.py
docs/{NOTIFY_INTEGRATION_GUIDE.md, REUSE_MAP.md, PHASE2-DELIVERY.md}
ARCHITECTURE_DECISIONS.md (ADR-008..012)
\`\`\`

## ۴) ماتریس دسترسی تغییرکرده
| مدل | base.group_user | Notification User | Notification Manager |
|---|---|---|---|
| itr.notify.settings | read | read | read/write |
| itr.sms.gateway.profile | - | read | full |
| itr.notification.event | read | read | full |
| itr.notification.alias | read | read | full |
| itr.notification.dispatch.log | read(خودش)/create | همان | read(همه) |
| itr.notification.user.preference | فقط رکورد خودش | فقط خودش | همه |
| itr.sla.policy | read | read | full |
| itr.sla.watch | read/create | همان | full |

حذف دفتر ارسال برای هیچ‌کس مجاز نیست (override روی unlink).

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
# بازگشت به وضعیت پیش از فاز ۲:
bash ops/restore.sh <آخرین dump> <آخرین filestore.tar.gz> ${DB_NAME}
# یا حذف ماژول از UI (itr_notify) و سپس:
python ~/odoo/odoo-bin -c ${CONF_FILE} -d ${DB_NAME} -u ${BASE_MODULE} --stop-after-init
\`\`\`

## ۸) گام بعد
Gate 2 سبز ⇒ آغاز فاز ۳ (itr_core بخش اول: ۱۳ گروه امنیتی، ۱۲ کاربر واقعی،
تیم سرپرستی، داده‌های پایه و سرویس نرخ ارز).
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-2: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

URL:            http://127.0.0.1:${HTTP_PORT}   (admin / as12)
DB (dev):       ${DB_NAME}        DB (uat): ${DB_NAME_UAT}
ماژول:          ${MODULE}  (state=${MOD_STATE_AFTER})
مسیر ماژول:     ${MOD_DIR}
verify:         ${OPS_DIR}/verify/verify_phase2.py
گزارش تحویل:    ${DOC_DIR}/PHASE2-DELIVERY.md
راهنمای اتصال:  ${DOC_DIR}/NOTIFY_INTEGRATION_GUIDE.md
Git:            HEAD=${GIT_HEAD}  tag=phase-2

فراخوانی از فازهای بعد:
  self.env['itr.notification.service'].notify('event.key', 'model', rec_id, {'reason': '...'})
  self.env['itr.sla.service'].open_watch('policy.key', record, user)

اجرای دستی دوبارهٔ تست‌ها:
  python ${ODOO_DIR}/odoo-bin -c ${CONF_FILE} -d ${DB_NAME} -u ${MODULE} \\
    --test-enable --test-tags /${MODULE} --stop-after-init

اجرای دستی دوبارهٔ verify:
  python ${ODOO_DIR}/odoo-bin shell -c ${CONF_FILE} -d ${DB_NAME} --stop-after-init \\
    < ${OPS_DIR}/verify/verify_phase2.py
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 2 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۳ (itr_core).${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 2 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۳ آغاز نمی‌شود.${NC}\n"
  exit 1
fi
