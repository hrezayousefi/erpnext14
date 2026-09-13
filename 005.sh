#!/usr/bin/env bash
# =============================================================================
# script-05-sales-slip-transport-seed.sh (005.sh) — PHASE 5 (COMPLETE)
# Iran Trade & Transport ERP — Odoo 19.0 | File-First | Idempotent | Test-First
# Gate-Enforced | No sudo-proof
#
# فاز ۵ — ریزفاکتور فروش و ایجاد خودکار پروندهٔ حمل
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt ← «فاز ۵» بندهای 5.1..5.9
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۳ (ریزفاکتور ≠ پیش‌فاکتور)،
#       BR-002 (رابطهٔ ۱..N هرگز یکتا)، BR-004، G03، BR-052/BR-055، بخش ۷ (نقشهٔ
#       خط‌وفلش: «حیدری: صدور ۱..N ریزفاکتور → ایجاد خودکار idempotent Transport Case
#       → کارتابل سرپرست حمل»)، بخش ۱۲ (پایهٔ کارتابل)، G15/G18
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh … 004.sh همین مخزن.
#
# پوشش کامل چک‌لیست فاز ۵:
#   5.1  مدل itr.sales.slip با گارد نقشی سرور: فقط finance_user/finance_supervisor/CEO
#        می‌سازد؛ گروه‌های حمل حتی از API مستقیم رد می‌شوند (ACL + گارد create).
#   5.2  گارد سرور: ساخت پیش از signed_document روی پروندهٔ مادر مسدود (حتی مدیر
#        سیستم)، مگر group_itr_validation_override + دلیل + ردیف اجباری در دفتر عبور.
#   5.3  کنترل سقف تناژ: Σ allocated_tonnage یک ردیف کالا ≤ تناژ قراردادی همان ردیف.
#   5.4  متد receive_by_transport(): تنها راه اطلاع واحد حمل؛ فاکتور نمی‌سازد، فقط
#        itr.transport.case می‌سازد (قرارداد در itr_core، پیاده‌سازی در itr_transport).
#   5.5  ایجاد خودکار itr.transport.case با کلید Idempotency (sales_slip_id +
#        dispatch_no) = UNIQUE واقعی دیتابیس + قفل تراکنشی SELECT … FOR UPDATE.
#   5.6  snapshot کامل فیلدها با مرجع منبع (BR-052): شمارهٔ خرید/فروش، تاریخ، کارخانه،
#        مشتری، کالا/ابعاد/شرح، تناژ، مبالغ خرید/فروش پایه، مقصد، مرز، نوع تحویل.
#   5.7  ★ شمارهٔ فاکتور هر بارگیری از ریزفاکتور خودش می‌آید نه سربرگ پرونده (BR-055).
#   5.8  رابطهٔ ۱ به N (چند پروندهٔ حمل برای یک ریزفاکتور) — هرگز unique.
#   5.9  اکشن «تحویل به واحد حمل» + رویداد اعلان slip.issued_to_transport.
#
# معماری (ADR-023): ریزفاکتور سند مالی است ⇒ در itr_core (بخش سوم). پروندهٔ حمل
#   سند میدانی است ⇒ ماژول جدید itr_transport (اسکلت این فاز؛ فاز ۶ همین ماژول را
#   با _inherit گسترش می‌دهد و هیچ فایل فاز ۵ را بازنویسی نمی‌کند). ترتیب Q02 حفظ:
#   itr_core هرگز به itr_transport وابسته نمی‌شود؛ receive_by_transport() قرارداد
#   را در core تعریف و itr_transport با _inherit پیاده می‌کند (الگوی hook).
#
# پوشش دغدغه‌های ثبت‌شدهٔ کارفرما (بدون اختلال در چک‌لیست رسمی):
#   [C1] کارتابل/ارجاع/فضای کاربری: mixin واحد itr.cartable.mixin (همان قرارداد
#        فاز ۴: current_owner_id + owner_deadline + assign_to() + _hand_over_to_group()
#        با «کم‌بارترین» G15 + لاگ افزودنی) برای ریزفاکتور و پروندهٔ حمل؛ trade.case
#        فاز ۴ دست‌نخورده می‌ماند (قرارداد یکسان، بدون موتور دوم — G18/ADR-019).
#   [C2] ریسک فایل‌های مشترک: هیچ فایل فاز ۳/۴ بازنویسی نمی‌شود؛ فقط فایل‌های جدید +
#        پچ افزایشی idempotent همان پنج فایل مشترک (manifest, models/__init__,
#        tests/__init__, ACL csv, fa_IR.po) + fingerprint قرارداد فازهای ۱..۴ در
#        preflight + پشتیبان DB و کپی timestamp دار فایل‌ها + بازاجرای تست‌های ۳ و ۴.
#        ★ تنها استثنای آگاهانه [FIX-P4-1]: تست/verify فاز ۴ «نبودِ مدل itr.sales.slip»
#        را assert می‌کرد که ذاتاً فازمحور است و با تحویل فاز ۵ قطعاً می‌شکست؛ همان
#        دو خط با جایگزین معنایی BR-004 («هیچ ریزفاکتوری برای پروندهٔ در انتظار
#        تأمین وجود ندارد») پچ لنگرشده، idempotent و با پشتیبان می‌شوند.
#   [C4] اصلاح اشتباه فاز ۳ [FIX-P3-1]: مقدار 'iranian' به سرویس Guarded داده می‌شد
#        ولی سرویس فقط 'ir' را ایرانی می‌شناخت ⇒ سنجهٔ کد ملی/پلاک ایرانی دور زده
#        می‌شد. اصلاح با _inherit روی itr.validation.service (نرمال‌سازی نام مستعار)
#        بدون دست‌زدن به فایل‌های فاز ۱/۳ + تست منفی.
#   [C4] محافظت FIN-014 [FIX-P4-2]: ردیف کالا پس از ورود به تأییدات/امضا دیگر
#        تناژ/نرخ/ارز/نوع ردیف را نمی‌پذیرد (فاز ۴ فقط UI را قفل کرده بود)؛ فیلدهای
#        reserved/effective فقط با context موتور تناژ نوشته می‌شوند (تعهد مستند فاز ۴).
#   [C3] گپ SRS: هیچ ماژول CRM نصب/وابسته نمی‌شود (BR-051/X16) — grep اثبات‌شده.
#
# پیش‌نیاز: Gate 4 سبز (bash 004.sh → itr_core بخش دوم نصب و installed)
#
# استفاده:
#   chmod +x 005.sh
#   bash 005.sh
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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase5-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase5-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase5-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase5-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase5-uat.log}"

CORE_MODULE="itr_core"
TRN_MODULE="itr_transport"
BASE_MODULE="itr_base"
NOTIFY_MODULE="itr_notify"
CORE_DIR="${CUSTOM_ADDONS}/${CORE_MODULE}"
TRN_DIR="${CUSTOM_ADDONS}/${TRN_MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P5_BACKUP_DIR="${DOC_DIR}/phase5-backup"

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
step "0) preflight — Gate 4 سبز + fingerprint قرارداد فازهای ۱/۲/۳/۴ (C2)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد: ${CONF_FILE} (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/${BASE_MODULE}" ]]   || err "ماژول ${BASE_MODULE} یافت نشد (ابتدا فاز ۱)"
[[ -d "${CUSTOM_ADDONS}/${NOTIFY_MODULE}" ]] || err "ماژول ${NOTIFY_MODULE} یافت نشد (ابتدا فاز ۲)"
[[ -d "${CORE_DIR}" ]]                       || err "ماژول ${CORE_MODULE} یافت نشد (ابتدا فاز ۳/۴)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G5-00" "نسخهٔ Odoo 19 تأیید شد" "PASS" "${ODOO_V}"
else
  gate "G5-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "نسخهٔ یافت‌شده: ${ODOO_V}"
  err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود."
fi

BASE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${BASE_MODULE}'")"
NOTIFY_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${NOTIFY_MODULE}'")"
CORE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TC_TABLE="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_trade_case')")"
if [[ "${BASE_STATE}" == "installed" && "${NOTIFY_STATE}" == "installed" && "${CORE_STATE}" == "installed" && "${TC_TABLE}" == "itr_trade_case" ]]; then
  gate "G5-01" "پیش‌نیازهای فاز ۱..۴ سبز هستند (Q02/Q08)" "PASS" "base/notify/core=installed, itr_trade_case موجود"
else
  gate "G5-01" "پیش‌نیازهای فاز ۱..۴ سبز هستند (Q02/Q08)" "FAIL" "base=${BASE_STATE:-?} notify=${NOTIFY_STATE:-?} core=${CORE_STATE:-?} tc=${TC_TABLE:-none}"
  err "طبق Q08، فازهای ۱ تا ۴ باید پیش از فاز ۵ نصب و سبز باشند."
fi

CONTRACT_FAILS=()
contract() {  # $1=شرح $2=فایل $3=الگوی grep -E
  if grep -qE "$3" "$2" 2>/dev/null; then info "contract OK: $1"; else CONTRACT_FAILS+=("$1 → الگوی «$3» در $2 یافت نشد"); fi
}
contract "P1: سرویس اعتبارسنجی Guarded"          "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "_name = \"itr.validation.service\""
contract "P1: امضای check_plate(value, plate_type)" "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "def check_plate\("
contract "P1: دفتر عبور + CHECK_KINDS"            "${CUSTOM_ADDONS}/itr_base/models/itr_validation_bypass_log.py" "CHECK_KINDS = \["
contract "P2: امضای notify()"                     "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_service.py" "def notify\(self, event_key, res_model=None, res_id=None, context=None\)"
contract "P2: _blocked_user_ids روی مدل رویداد"   "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_event.py" "def _blocked_user_ids"
contract "P3: سرویس نرخ ارز apply_fx"             "${CORE_DIR}/models/itr_fx_service.py" "def apply_fx\(self, amount, from_currency, to_currency=None, date=None\)"
contract "P3: سرویس نرخ ارز resolve_rate"         "${CORE_DIR}/models/itr_fx_service.py" "def resolve_rate\("
contract "P3: تیم سرپرستی get_subordinate_users"  "${CORE_DIR}/models/itr_supervisor_team.py" "def get_subordinate_users"
contract "P4: مدل پروندهٔ بازرگانی"               "${CORE_DIR}/models/itr_trade_case.py" "_name = \"itr.trade.case\""
contract "P4: گذار approved → slips_issued"       "${CORE_DIR}/models/itr_trade_case.py" "\"approved\": \{\"slips_issued\"\}"
contract "P4: گذار slips_issued → closed"         "${CORE_DIR}/models/itr_trade_case.py" "\"slips_issued\": \{\"closed\"\}"
contract "P4: STATE_ENGINE_CTX"                   "${CORE_DIR}/models/itr_trade_case.py" "STATE_ENGINE_CTX = \"itr_trade_state_engine\""
contract "P4: mark_slips_issued()"                "${CORE_DIR}/models/itr_trade_case.py" "def mark_slips_issued"
contract "P4: _hand_over_to_group()"              "${CORE_DIR}/models/itr_trade_case.py" "def _hand_over_to_group\(self, group_xmlid, summary\)"
contract "P4: ردیف کالا reserved/effective"       "${CORE_DIR}/models/itr_trade_case_item.py" "reserved_tonnage = fields.Float"
contract "P4: ردیف کالا lock_rates()"             "${CORE_DIR}/models/itr_trade_case_item.py" "def lock_rates"
contract "P4: موتور مالی واحد case_totals()"      "${CORE_DIR}/models/money_engine.py" "def case_totals\(self, case\)"
contract "P4: اسکلت دفتر طلب"                     "${CORE_DIR}/models/itr_factory_shortfall.py" "_name = \"itr.factory.shortfall\""
contract "P4: لنگر manifest (منوی فاز ۴)"          "${CORE_DIR}/__manifest__.py" "views/itr_core_phase4_menus.xml"
contract "P4: نسخهٔ manifest 19.0.1.1.0"           "${CORE_DIR}/__manifest__.py" "\"version\": \"19.0.1.1.0\""
contract "P4: فرم پروندهٔ بازرگانی (xmlid)"        "${CORE_DIR}/views/itr_trade_case_views.xml" "id=\"view_itr_trade_case_form\""
contract "P4: تست فازمحور BR-004 (هدف FIX-P4-1)"   "${CORE_DIR}/tests/test_trade_case_phase4.py" "itr.sales.slip"
GROUPS_OK=1
for g in group_ceo group_financial_manager group_finance_supervisor group_finance_user \
         group_transport_supervisor group_transport_docs group_customs_officer group_transport_delivery group_auditor; do
  GID="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core' AND name='${g}'")"
  [[ "${GID}" == "1" ]] || { GROUPS_OK=0; CONTRACT_FAILS+=("گروه ${g} در دیتابیس یافت نشد"); }
done
EV_BACK="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key='trade_case.back_to_finance_supervisor'")"
[[ "${EV_BACK}" == "1" ]] || CONTRACT_FAILS+=("رویداد حیاتی فاز ۴ در دیتابیس نیست")
if [[ ${#CONTRACT_FAILS[@]} -eq 0 && ${GROUPS_OK} -eq 1 ]]; then
  gate "G5-02" "fingerprint قرارداد فازهای ۱..۴ منطبق است (C2 / پیوست ج)" "PASS" "22 contract + 9 group + 1 event"
else
  gate "G5-02" "fingerprint قرارداد فازهای ۱..۴ منطبق است (C2 / پیوست ج)" "FAIL" "$(printf '%s | ' "${CONTRACT_FAILS[@]}")"
  err "قرارداد فازهای قبل مطابق فرض فاز ۵ نیست — طبق پیوست ج، فاز متوقف شد. هیچ فایلی تغییر نکرد."
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
step "2) پشتیبان DB پیش از ارتقا (Q10/NFR-005) + پشتیبان فایل‌های مشترک (C2)"
# =============================================================================
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G5-03" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "SKIP_BACKUP=1"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  BK_OUT="$(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)"
  BK_DUMP="$(echo "${BK_OUT}" | head -n1)"
  if [[ -s "${BK_DUMP:-/nonexistent}" ]]; then
    gate "G5-03" "پشتیبان پیش از ارتقا گرفته شد" "PASS" "$(basename "${BK_DUMP}")"
  else
    gate "G5-03" "پشتیبان پیش از ارتقا گرفته شد" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G5-03" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "ops/backup.sh یافت نشد"
fi

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${P5_BACKUP_DIR}/${TS}"
for f in "__manifest__.py" "models/__init__.py" "tests/__init__.py" \
         "security/ir.model.access.csv" "i18n/fa_IR.po" "i18n/fa.po" \
         "tests/test_trade_case_phase4.py"; do
  if [[ -f "${CORE_DIR}/${f}" ]]; then
    mkdir -p "${P5_BACKUP_DIR}/${TS}/${CORE_MODULE}/$(dirname "${f}")"
    cp -f "${CORE_DIR}/${f}" "${P5_BACKUP_DIR}/${TS}/${CORE_MODULE}/${f}"
  fi
done
[[ -f "${OPS_DIR}/verify/verify_phase4.py" ]] && { mkdir -p "${P5_BACKUP_DIR}/${TS}/ops/verify"; cp -f "${OPS_DIR}/verify/verify_phase4.py" "${P5_BACKUP_DIR}/${TS}/ops/verify/"; }
log "کپی امن فایل‌های مشترک در ${P5_BACKUP_DIR}/${TS}"

# =============================================================================
step "3) فایل‌های *جدید* itr_core (بخش سوم) — هیچ فایل فاز ۳/۴ بازنویسی نمی‌شود"
# =============================================================================
mkdir -p "${CORE_DIR}"/{models,security,data,views,i18n,tests}
mkdir -p "${OPS_DIR}/verify" "${DOC_DIR}"
find "${CORE_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# ------------------------------------------ models/itr_cartable_mixin.py --
write_utf8 "${CORE_DIR}/models/itr_cartable_mixin.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""THE cartable contract shared by every work item after phase 4 (concern C1).

Phase 4 implemented current_owner_id / owner_deadline / assign_to() /
_hand_over_to_group() directly on itr.trade.case (ADR-019). This mixin
re-exposes EXACTLY the same contract for every later work item (sales slip,
transport case, payment request) so phase 8 can build ONE Unified Work Queue
on three identical fields/methods (UX-011) - never a second task engine (G18).

Rules honoured here
-------------------
* SRS glossary: Assignment = owner change + cartable record + notification
  (activity) + history. The word "release" is banned.
* G15: initial hand-over goes to the least-loaded eligible user of a group.
* SEC-002 / Q03: Administrator, OdooBot and archived users never own work.
* SEC-004: a supervisor may only assign inside his own team (phase-3 model).
* Q07: the assignment deadline is a parameter, never hard coded.
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

CARTABLE_ENGINE_CTX = "itr_cartable_engine"
TERMINAL_STATES = ("closed", "cancelled", "rejected", "settled", "executed", "handed_over")


class ItrCartableMixin(models.AbstractModel):
    _name = "itr.cartable.mixin"
    _description = "ITR Cartable Mixin"

    current_owner_id = fields.Many2one(
        "res.users", string="Current owner", index=True, copy=False,
        help="The user whose desk this work item sits on right now (UX-011).",
    )
    owner_deadline = fields.Datetime(string="Owner deadline", copy=False)

    # ------------------------------------------------------------ helpers
    def _cartable_open_domain(self):
        """Domain of 'still open' records of this model (workload basis)."""
        if "state" in self._fields:
            return [("state", "not in", TERMINAL_STATES)]
        return []

    @api.model
    def _cartable_blocked_user_ids(self):
        return self.env["itr.notification.event"]._blocked_user_ids()

    def _itr_notify(self, event_key, extra=None):
        """The ONLY alert path (NOT-001) - notify() never raises."""
        self.ensure_one()
        context = {"occurrence_id": "%s-%s-%s" % (self._name, self.id, event_key)}
        context.update(extra or {})
        return self.env["itr.notification.service"].notify(
            event_key, self._name, self.id, context)

    # ---------------------------------------------------------- assignment
    def _assign_internal(self, user, reason):
        """Owner change + append-only log + activity + chatter (never less)."""
        self.ensure_one()
        blocked = self._cartable_blocked_user_ids()
        if not user or not user.active or user.id in blocked:
            raise UserError(
                _("Administrator, OdooBot or an archived user can never own a "
                  "work item (SEC-002)."))
        previous = self.current_owner_id
        days = int(self.env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
            "itr_core.default_assignment_days", "2"))
        deadline = fields.Datetime.add(fields.Datetime.now(), days=days)
        self.with_context(**{CARTABLE_ENGINE_CTX: True}).write({
            "current_owner_id": user.id,
            "owner_deadline": deadline,
        })
        self.env["itr.work.assignment.log"].create({
            "res_model": self._name,
            "res_id": self.id,
            "record_display": self.display_name,
            "from_user_id": previous.id if previous else False,
            "to_user_id": user.id,
            "reason": reason or _("Assignment"),
            "state_at_assignment": self.state if "state" in self._fields else False,
        })
        if hasattr(self, "activity_schedule"):
            self.activity_schedule(
                "mail.mail_activity_data_todo",
                user_id=user.id,
                summary=reason or _("Work item assignment"),
                date_deadline=fields.Date.to_date(deadline),
            )
        if hasattr(self, "message_post"):
            self.message_post(body=_(
                "Assigned to <b>%(to)s</b> by %(by)s. Reason: %(reason)s",
                to=user.display_name, by=self.env.user.display_name,
                reason=reason or "-",
            ))
        return True

    def assign_to(self, user, reason=None):
        """The ONLY legal reassignment path (same contract as phase 4)."""
        self.ensure_one()
        if not (reason or "").strip():
            raise UserError(_("A reassignment always requires a mandatory reason."))
        if "state" in self._fields and self.state in TERMINAL_STATES:
            raise UserError(_("A terminal work item cannot be reassigned."))
        actor = self.env.user
        unrestricted = (
            actor.has_group("itr_core.group_ceo")
            or actor.has_group("itr_core.group_financial_manager")
        )
        if not unrestricted:
            subordinates = self.env["itr.supervisor.team"].get_subordinate_users(actor.id)
            if user not in subordinates and user != actor:
                raise UserError(
                    _("A supervisor may only assign work to a member of his "
                      "own team (SEC-004)."))
        return self._assign_internal(user, reason)

    def _hand_over_to_group(self, group_xmlid, summary):
        """Move the desk to the least-loaded eligible member of a group (G15)."""
        self.ensure_one()
        group = self.env.ref(group_xmlid, raise_if_not_found=False)
        if not group:
            return False
        blocked = self._cartable_blocked_user_ids()
        users = group.users if "users" in group._fields else group.user_ids
        candidates = [u for u in users if u.active and u.id not in blocked]
        if not candidates:
            return False
        open_domain = self._cartable_open_domain()
        loads = {
            u.id: self.search_count([("current_owner_id", "=", u.id)] + open_domain)
            for u in candidates
        }
        target = min(candidates, key=lambda u: (loads[u.id], u.id))
        self._assign_internal(target, summary)
        return target
PYEOF

# ------------------------------------- models/itr_work_assignment_log.py --
write_utf8 "${CORE_DIR}/models/itr_work_assignment_log.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Append-only assignment history of every cartable work item (C1 / REQ-002).

itr.case.assignment.log (phase 4) stays the history of the trade case; this
generic log is the history of every OTHER work item (sales slip, transport
case, payment request). Both are pure history - deliberately NOT a task queue
(G18). Phase 8 reads the union of both for the audit trail.
"""
from odoo import _, fields, models
from odoo.exceptions import UserError


class ItrWorkAssignmentLog(models.Model):
    _name = "itr.work.assignment.log"
    _description = "Work Item Assignment Log"
    _order = "id desc"

    res_model = fields.Char(string="Model", required=True, readonly=True, index=True)
    res_id = fields.Integer(string="Record id", required=True, readonly=True, index=True)
    record_display = fields.Char(string="Record", readonly=True)
    from_user_id = fields.Many2one("res.users", string="From", readonly=True, ondelete="restrict")
    to_user_id = fields.Many2one("res.users", string="To", required=True, readonly=True,
                                 ondelete="restrict", index=True)
    reason = fields.Text(string="Reason", required=True, readonly=True)
    state_at_assignment = fields.Char(string="State at assignment", readonly=True)
    assigned_by_id = fields.Many2one(
        "res.users", string="Assigned by", required=True, readonly=True,
        default=lambda self: self.env.user)
    assigned_on = fields.Datetime(
        string="Assigned on", required=True, readonly=True, default=fields.Datetime.now)

    def write(self, vals):
        raise UserError(_("Assignment log records are append-only and cannot be modified."))

    def unlink(self):
        raise UserError(_("Assignment log records are append-only and cannot be deleted."))
PYEOF

# ------------------------------------ models/itr_validation_service_ext.py --
write_utf8 "${CORE_DIR}/models/itr_validation_service_ext.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""[FIX-P3-1] Alias normalisation of the guarded validation layer.

Phase 1 recognises ONLY 'ir' as the Iranian nationality / plate type, while
phase 3 models (itr.driver, itr.vehicle, res.partner) pass 'iranian'. The
guarded checks were therefore silently skipped for Iranian people and plates
(phase 3 masked it for drivers with a local checksum copy). Fixed here by
inheritance - no phase-1 or phase-3 file is rewritten (concern C2/C4).

Also registers the 'workflow_override' audit kind used by the phase-5
signature guard bypass (checklist 5.2) - selection_add, never a rewrite.
"""
from odoo import api, fields, models

IRANIAN_ALIASES = {"ir", "iranian", "iran", "irn", "domestic"}


class ItrValidationBypassLogExt(models.Model):
    _inherit = "itr.validation.bypass.log"

    check_kind = fields.Selection(
        selection_add=[("workflow_override", "Workflow guard override")],
        ondelete={"workflow_override": "cascade"},
    )


class ItrValidationServiceExt(models.AbstractModel):
    _inherit = "itr.validation.service"

    @api.model
    def normalize_origin(self, value):
        """'iranian' / 'IR' / 'iran' -> 'ir'; anything else -> 'foreign'."""
        text = str(value or "ir").strip().lower()
        return "ir" if text in IRANIAN_ALIASES else "foreign"

    @api.model
    def check_national_id(self, value, nationality="ir", res_model=None, res_id=None):
        return super().check_national_id(
            value, nationality=self.normalize_origin(nationality),
            res_model=res_model, res_id=res_id)

    @api.model
    def check_plate(self, value, plate_type="ir", res_model=None, res_id=None):
        return super().check_plate(
            value, plate_type=self.normalize_origin(plate_type),
            res_model=res_model, res_id=res_id)
PYEOF

# ------------------------------------------------ models/itr_sales_slip.py --
write_utf8 "${CORE_DIR}/models/itr_sales_slip.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Trade sales slip (checklist 5.1 .. 5.9 / SRS section 3, BR-002, BR-004, G03).

* A sales slip is the BINDING financial document the finance unit issues per
  retail buyer, ONLY after the physical signature (G03). It is never the
  operational proforma (X04) and never an Odoo invoice.
* Relationship (BR-002): Trade Case (1) --< Sales Slip (1..N) --< Transport
  Case (1..N). Nothing here is ever unique.
* receive_by_transport() is the ONLY door through which the transport unit
  learns about a slip (5.4). It creates NO invoice; it creates transport
  cases. The contract lives here; itr_transport implements
  _create_transport_cases() by inheritance (Q02: itr_core never depends on
  itr_transport).
* "CRM" (BR-051 / X16) means exactly this hand-over hook: a data transfer
  from the commercial file to the operational file. No CRM module is
  installed or depended upon (grep-enforced by the phase gate).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

SLIP_STATES = [
    ("draft", "Draft"),
    ("issued", "Issued"),
    ("handed_over", "Handed over to transport"),
    ("cancelled", "Cancelled"),
]

SLIP_ENGINE_CTX = "itr_sales_slip_engine"
TONNAGE_ENGINE_CTX = "itr_tonnage_engine"

SLIP_ISSUER_GROUPS = (
    "itr_core.group_finance_user",
    "itr_core.group_finance_supervisor",
    "itr_core.group_ceo",
)

DELIVERY_MODES = [
    ("factory_to_customer", "Factory door to customer address"),
    ("factory_to_border", "Factory door to exit border"),
    ("other", "Other (see notes)"),
]


class ItrSalesSlip(models.Model):
    _name = "itr.sales.slip"
    _description = "Trade Sales Slip"
    _inherit = ["mail.thread", "mail.activity.mixin", "itr.cartable.mixin"]
    _order = "id desc"

    name = fields.Char(string="Slip number", required=True, copy=False, readonly=True,
                       index=True, default=lambda self: _("New"))
    company_id = fields.Many2one("res.company", string="Company", required=True, index=True,
                                 default=lambda self: self.env.company)
    case_id = fields.Many2one(
        "itr.trade.case", string="Trade case", required=True, ondelete="restrict",
        index=True, tracking=True,
        domain=[("state", "in", ("approved", "slips_issued"))],
    )
    customer_id = fields.Many2one("res.partner", string="Buyer", required=True, tracking=True)
    slip_date = fields.Date(string="Slip date", required=True, default=fields.Date.context_today)
    state = fields.Selection(SLIP_STATES, string="State", required=True, default="draft",
                             index=True, tracking=True, copy=False)
    line_ids = fields.One2many("itr.sales.slip.line", "slip_id", string="Lines")

    destination = fields.Char(string="Destination")
    border_id = fields.Many2one("itr.border", string="Exit border")
    delivery_mode = fields.Selection(DELIVERY_MODES, string="Delivery mode",
                                     default="factory_to_customer", required=True)
    dispatch_count = fields.Integer(
        string="Planned loadings", default=1,
        help="Number of transport cases (trucks) created at hand-over (1..N, BR-002). "
             "More can be added later with receive_by_transport(n).")

    total_tonnage = fields.Float(string="Total allocated tonnage", compute="_compute_totals", store=True)
    total_sale_base = fields.Float(string="Total sale (IRR)", compute="_compute_totals", store=True)

    handed_over_on = fields.Datetime(string="Handed over on", readonly=True, copy=False)
    handed_over_by_id = fields.Many2one("res.users", string="Handed over by", readonly=True, copy=False)
    issued_on = fields.Datetime(string="Issued on", readonly=True, copy=False)
    issued_by_id = fields.Many2one("res.users", string="Issued by", readonly=True, copy=False)
    cancel_reason = fields.Text(string="Cancellation reason", readonly=True, copy=False)
    note = fields.Text(string="Notes")

    # ------------------------------------------------------------ computes
    @api.depends("line_ids.allocated_tonnage", "line_ids.base_amount")
    def _compute_totals(self):
        for slip in self:
            slip.total_tonnage = sum(slip.line_ids.mapped("allocated_tonnage"))
            slip.total_sale_base = sum(slip.line_ids.mapped("base_amount"))

    @api.constrains("dispatch_count")
    def _check_dispatch_count(self):
        for slip in self:
            if slip.dispatch_count < 1:
                raise ValidationError(_("A sales slip plans at least one loading."))

    # ------------------------------------------------------------- guards
    @api.model
    def _check_issuer_role(self):
        """5.1: only the finance unit; a raw RPC call by transport is refused too."""
        if self.env.su:
            raise UserError(_("Business documents are never issued as superuser (G01/Q03)."))
        user = self.env.user
        if not any(user.has_group(xmlid) for xmlid in SLIP_ISSUER_GROUPS):
            raise UserError(
                _("Only the finance unit (finance specialist, finance supervisor or "
                  "CEO) may create or issue a sales slip (checklist 5.1)."))

    def _check_signature_guard(self, case):
        """5.2 / G03 / BR-004: no slip before the signed purchase document."""
        if not case:
            raise UserError(_("A sales slip always belongs to a trade case."))
        if case.state in ("approved", "slips_issued") and case.signed_document:
            return True
        reason = (self.env.context.get("itr_override_reason") or "").strip()
        if self.env.user.has_group("itr_base.group_itr_validation_override") and reason:
            self.env["itr.validation.service"].log_bypass(
                "workflow_override",
                "sales_slip_before_signature:%s" % case.name,
                res_model=case._name, res_id=case.id,
                reason=_("Signature guard bypassed for sales slip creation: %(r)s", r=reason),
            )
            return True
        raise UserError(
            _("A sales slip can only be issued after the signed, scanned purchase "
              "document is uploaded on the trade case (G03 / BR-004). Case %(c)s is "
              "in state %(s)s.", c=case.name, s=case.state))

    @api.model_create_multi
    def create(self, vals_list):
        self._check_issuer_role()
        for vals in vals_list:
            case = self.env["itr.trade.case"].browse(vals.get("case_id"))
            self._check_signature_guard(case.exists())
            if vals.get("state") and vals["state"] != "draft":
                raise UserError(_("A sales slip always starts in draft."))
            if not vals.get("name") or vals.get("name") == _("New"):
                vals["name"] = self.env["ir.sequence"].next_by_code("itr.sales.slip") or _("New")
            vals.setdefault("company_id", case.company_id.id or self.env.company.id)
            vals.setdefault("current_owner_id", self.env.user.id)
        return super().create(vals_list)

    def write(self, vals):
        if "state" in vals and not self.env.context.get(SLIP_ENGINE_CTX):
            raise UserError(
                _("The slip state can only change through its official actions."))
        if "case_id" in vals:
            for slip in self:
                if slip.case_id and vals["case_id"] != slip.case_id.id:
                    raise UserError(_("A sales slip can never be moved to another trade case."))
        return super().write(vals)

    def unlink(self):
        for slip in self:
            if slip.state != "draft":
                raise UserError(_("Only a draft sales slip can be deleted (OPS-027)."))
        return super().unlink()

    def _set_state(self, state):
        return self.with_context(**{SLIP_ENGINE_CTX: True}).write({"state": state})

    # ------------------------------------------------------------- actions
    def action_issue(self):
        """draft -> issued: locks the sale rates and reserves the tonnage."""
        self._check_issuer_role()
        for slip in self:
            if slip.state != "draft":
                raise UserError(_("Only a draft slip can be issued."))
            if not slip.line_ids:
                raise UserError(_("A sales slip needs at least one line."))
            slip._check_signature_guard(slip.case_id)
            slip.line_ids._lock_rates()
            slip.with_context(**{SLIP_ENGINE_CTX: True}).write({
                "issued_on": fields.Datetime.now(),
                "issued_by_id": self.env.user.id,
            })
            slip._set_state("issued")
            if slip.case_id.state == "approved":
                slip.case_id.mark_slips_issued()
            slip.line_ids.mapped("case_item_id")._recompute_reserved_tonnage()
            slip.message_post(body=_("Sales slip issued by %(u)s.", u=self.env.user.display_name))
        return True

    def action_hand_over_to_transport(self):
        """5.9: issued -> handed_over + transport cases + slip.issued_to_transport."""
        self._check_issuer_role()
        for slip in self:
            if slip.state not in ("issued", "handed_over"):
                raise UserError(_("Only an issued slip can be handed over to transport."))
            created = slip.receive_by_transport()
            if slip.state == "issued":
                slip.with_context(**{SLIP_ENGINE_CTX: True}).write({
                    "handed_over_on": fields.Datetime.now(),
                    "handed_over_by_id": self.env.user.id,
                })
                slip._set_state("handed_over")
                slip._itr_notify("slip.issued_to_transport", {"loadings": len(created)})
            slip.message_post(body=_(
                "Handed over to transport: %(n)s new transport case(s).", n=len(created)))
        return True

    def receive_by_transport(self, dispatch_count=None):
        """5.4: THE only way the transport unit is informed about a slip.

        Creates NO invoice and NO accounting entry (FIN-016); it only creates
        transport cases, idempotently (5.5). Re-running it never duplicates.
        """
        self.ensure_one()
        if self.state not in ("issued", "handed_over"):
            raise UserError(_("Transport can only receive an issued sales slip."))
        return self._create_transport_cases(dispatch_count)

    def _create_transport_cases(self, dispatch_count=None):
        """Hook implemented by itr_transport (Q02 layering)."""
        raise UserError(
            _("The transport module (itr_transport) is not installed, so no "
              "transport case can be created from sales slip %(n)s.", n=self.name))

    def _has_active_transport(self):
        """Hook implemented by itr_transport."""
        return False

    def action_cancel(self, reason=None):
        self._check_issuer_role()
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        if not reason:
            raise UserError(_("Cancelling a sales slip requires a mandatory reason."))
        for slip in self:
            if slip.state == "cancelled":
                continue
            if slip._has_active_transport():
                raise UserError(
                    _("Slip %(n)s has active transport cases; cancel them first.", n=slip.name))
            slip.with_context(**{SLIP_ENGINE_CTX: True}).write({"cancel_reason": reason})
            slip._set_state("cancelled")
            slip.line_ids.mapped("case_item_id")._recompute_reserved_tonnage()
            slip.message_post(body=_("Sales slip cancelled. Reason: %(r)s", r=reason))
        return True


class ItrSalesSlipLine(models.Model):
    _name = "itr.sales.slip.line"
    _description = "Trade Sales Slip Line"
    _order = "slip_id, sequence, id"

    slip_id = fields.Many2one("itr.sales.slip", string="Sales slip", required=True,
                              ondelete="cascade", index=True)
    sequence = fields.Integer(string="Sequence", default=10)
    case_id = fields.Many2one(related="slip_id.case_id", store=True, index=True, readonly=True)
    slip_state = fields.Selection(related="slip_id.state", store=True, readonly=True)
    case_item_id = fields.Many2one(
        "itr.trade.case.item", string="Goods row of the case", required=True,
        ondelete="restrict", index=True,
        domain="[('case_id', '=', case_id)]")
    goods_description = fields.Char(related="case_item_id.name", readonly=True)
    allocated_tonnage = fields.Float(string="Allocated tonnage", required=True)
    sale_price_unit = fields.Float(string="Sale rate / ton")
    currency_id = fields.Many2one("res.currency", string="Currency")
    sale_amount = fields.Float(string="Sale amount", compute="_compute_amount", store=True)
    fx_rate = fields.Float(string="Conversion rate", readonly=True)
    base_amount = fields.Float(string="Sale base amount (IRR)", readonly=True)
    rate_locked = fields.Boolean(string="Rate locked", readonly=True)

    @api.onchange("case_item_id")
    def _onchange_case_item(self):
        for line in self:
            if line.case_item_id:
                line.sale_price_unit = line.case_item_id.sale_price_unit
                line.currency_id = line.case_item_id.sale_currency_id

    @api.depends("allocated_tonnage", "sale_price_unit")
    def _compute_amount(self):
        for line in self:
            line.sale_amount = (line.allocated_tonnage or 0.0) * (line.sale_price_unit or 0.0)

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            item = self.env["itr.trade.case.item"].browse(vals.get("case_item_id"))
            if item and not vals.get("currency_id"):
                vals["currency_id"] = item.sale_currency_id.id
            if item and not vals.get("sale_price_unit"):
                vals["sale_price_unit"] = item.sale_price_unit
        return super().create(vals_list)

    @api.constrains("case_item_id", "slip_id")
    def _check_item_belongs_to_case(self):
        for line in self:
            if line.case_item_id.case_id != line.slip_id.case_id:
                raise ValidationError(
                    _("The goods row must belong to the same trade case as the slip."))

    @api.constrains("allocated_tonnage", "case_item_id", "slip_id")
    def _check_allocation_cap(self):
        """5.3: sum of allocations of one goods row <= its contract tonnage."""
        for line in self:
            if line.allocated_tonnage <= 0:
                raise ValidationError(_("The allocated tonnage must be greater than zero."))
            item = line.case_item_id
            total = sum(self.search([
                ("case_item_id", "=", item.id),
                ("slip_state", "!=", "cancelled"),
            ]).mapped("allocated_tonnage"))
            if total > item.contract_tonnage + 1e-6:
                raise ValidationError(
                    _("Total allocated tonnage %(alloc)s of goods row '%(item)s' exceeds "
                      "its contract tonnage %(contract)s (checklist 5.3).",
                      alloc=total, item=item.name, contract=item.contract_tonnage))

    def write(self, vals):
        locked_fields = {"allocated_tonnage", "sale_price_unit", "currency_id", "case_item_id"}
        for line in self:
            if line.slip_id.state != "draft" and locked_fields & set(vals):
                raise UserError(_("Lines of an issued slip are frozen (FIN-014)."))
        return super().write(vals)

    def _lock_rates(self):
        """FIN-014: every money event locks its own rate when it happens."""
        fx = self.env["itr.fx.service"]
        for line in self:
            if line.rate_locked:
                continue
            currency = line.currency_id or line.case_item_id.sale_currency_id
            result = fx.apply_fx(line.sale_amount, currency)
            line.write({
                "fx_rate": result["conversion_rate"],
                "base_amount": result["base_amount"],
                "rate_locked": True,
            })
        return True
PYEOF

# --------------------------------------- models/itr_trade_case_phase5.py --
write_utf8 "${CORE_DIR}/models/itr_trade_case_phase5.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase-5 extensions of the phase-4 models BY INHERITANCE (concern C2).

Nothing in itr_trade_case.py / itr_trade_case_item.py is rewritten:
* trade case: slip roll-ups, smart-button actions, and mark_slips_issued()
  widened to the three issuer roles of checklist 5.1 (finance specialist,
  finance supervisor, CEO) - phase 4 only allowed the specialist.
* goods row: [FIX-P4-2] server-side freeze of tonnage/rates/currency once the
  case entered the review chain (FIN-014 was UI-only in phase 4), reserved
  tonnage roll-up (phase 4 documented: "written by phase 5 only") and a guard
  so reserved/effective tonnage are only written by the tonnage engine.
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

from .itr_sales_slip import SLIP_ISSUER_GROUPS, TONNAGE_ENGINE_CTX

ITEM_FROZEN_FIELDS = {
    "contract_tonnage", "purchase_price_unit", "sale_price_unit",
    "purchase_currency_id", "sale_currency_id", "row_kind",
}
ITEM_EDITABLE_STATES = ("draft", "waiting_supply", "returned")
ENGINE_ONLY_FIELDS = {"reserved_tonnage", "effective_tonnage"}


class ItrTradeCase(models.Model):
    _inherit = "itr.trade.case"

    sales_slip_ids = fields.One2many("itr.sales.slip", "case_id", string="Sales slips")
    sales_slip_count = fields.Integer(string="Sales slips", compute="_compute_slip_stats")
    reserved_tonnage_total = fields.Float(
        string="Total reserved tonnage", compute="_compute_slip_stats",
        help="Sum of the tonnage allocated to issued (non-cancelled) sales slips.")

    @api.depends("sales_slip_ids.state", "sales_slip_ids.total_tonnage")
    def _compute_slip_stats(self):
        for case in self:
            active = case.sales_slip_ids.filtered(lambda s: s.state != "cancelled")
            case.sales_slip_count = len(active)
            case.reserved_tonnage_total = sum(
                active.filtered(lambda s: s.state != "draft").mapped("total_tonnage"))

    def mark_slips_issued(self):
        """approved -> slips_issued (widened to the 5.1 issuer roles)."""
        for case in self:
            if self.env.su:
                raise UserError(
                    _("Business transitions are never executed as superuser (G01/Q03)."))
            if not any(self.env.user.has_group(g) for g in SLIP_ISSUER_GROUPS):
                raise UserError(
                    _("Only the finance unit may mark the sales slips as issued."))
            if case.state != "approved":
                raise UserError(
                    _("Sales slips are marked as issued only from the approved "
                      "(signed) state; case %(c)s is in %(s)s.", c=case.name, s=case.state))
            case._do_transition("slips_issued")
        return True

    def action_open_sales_slips(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("Sales slips"),
            "res_model": "itr.sales.slip",
            "view_mode": "list,form",
            "domain": [("case_id", "=", self.id)],
            "context": {"default_case_id": self.id},
        }

    def action_new_sales_slip(self):
        """Shortcut only - the create() guards of the slip still apply (UX-021)."""
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("New sales slip"),
            "res_model": "itr.sales.slip",
            "view_mode": "form",
            "target": "current",
            "context": {
                "default_case_id": self.id,
                "default_customer_id": self.buyer_id.id,
                "default_border_id": self.border_id.id,
                "default_destination": self.destination,
            },
        }


class ItrTradeCaseItem(models.Model):
    _inherit = "itr.trade.case.item"

    slip_line_ids = fields.One2many("itr.sales.slip.line", "case_item_id", string="Slip lines")
    allocated_tonnage = fields.Float(
        string="Allocated to slips", compute="_compute_allocated", store=True,
        help="Sum of the tonnage allocated by non-cancelled sales slips (draft included).")

    @api.depends("slip_line_ids.allocated_tonnage", "slip_line_ids.slip_state")
    def _compute_allocated(self):
        for item in self:
            item.allocated_tonnage = sum(
                item.slip_line_ids.filtered(lambda l: l.slip_state != "cancelled")
                .mapped("allocated_tonnage"))

    def _recompute_reserved_tonnage(self):
        """Reserved = allocated by ISSUED / handed-over slips (SRS glossary)."""
        for item in self:
            reserved = sum(
                item.slip_line_ids.filtered(lambda l: l.slip_state in ("issued", "handed_over"))
                .mapped("allocated_tonnage"))
            item.with_context(**{TONNAGE_ENGINE_CTX: True}).write({"reserved_tonnage": reserved})
        return True

    def write(self, vals):
        if ENGINE_ONLY_FIELDS & set(vals) and not self.env.context.get(TONNAGE_ENGINE_CTX):
            raise UserError(
                _("Reserved / effective tonnage are written only by the tonnage engine "
                  "(phase 5 / phase 6), never by hand (OPS-023)."))
        if ITEM_FROZEN_FIELDS & set(vals) and not self.env.context.get(TONNAGE_ENGINE_CTX):
            for item in self:
                if item.case_id.state not in ITEM_EDITABLE_STATES:
                    raise UserError(
                        _("Goods row '%(n)s' is frozen: tonnage, rates, currency and row "
                          "kind cannot change once the case entered the review chain "
                          "(FIN-014). Return the case for completion first.", n=item.name))
        return super().write(vals)
PYEOF

# ------------------------------------------------ security (فایل جدید) --
write_utf8 "${CORE_DIR}/security/itr_core_phase5_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">
        <!-- SEC-012 company rules; the fine "mine / team / all" matrix is phase 7 -->
        <record id="rule_itr_sales_slip_company" model="ir.rule">
            <field name="name">Sales slip: company rule</field>
            <field name="model_id" ref="itr_core.model_itr_sales_slip"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
        <record id="rule_itr_sales_slip_line_company" model="ir.rule">
            <field name="name">Sales slip line: company rule</field>
            <field name="model_id" ref="itr_core.model_itr_sales_slip_line"/>
            <field name="domain_force">[('slip_id.company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${CORE_DIR}/data/itr_sales_slip_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="seq_itr_sales_slip" model="ir.sequence">
            <field name="name">Trade Sales Slip</field>
            <field name="code">itr.sales.slip</field>
            <field name="prefix">SS/%(range_year)s/</field>
            <field name="padding">5</field>
            <field name="company_id" eval="False"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${CORE_DIR}/data/itr_core_phase5_notify_events.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Phase 5 seeds ONLY the events its checklist mandates (5.9) - ADR-020:
         phase 10 refers to these xmlids, never re-creates the same event_key. -->
    <data noupdate="1">
        <record id="event_slip_issued_to_transport" model="itr.notification.event">
            <field name="event_key">slip.issued_to_transport</field>
            <field name="title">Sales slip handed over to the transport unit</field>
            <field name="category">transport</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor'))]"/>
            <field name="internal_subject">Sales slip {{name}} handed over to transport</field>
            <field name="internal_body">Sales slip {{name}} was handed over to the transport unit; {{loadings}} transport case(s) were created and wait for loading authorisation.</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${CORE_DIR}/views/itr_sales_slip_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_sales_slip_form" model="ir.ui.view">
        <field name="name">itr.sales.slip.form</field>
        <field name="model">itr.sales.slip</field>
        <field name="arch" type="xml">
            <form string="Sales Slip">
                <header>
                    <button name="action_issue" type="object" string="Issue slip" class="btn-primary"
                            invisible="state != 'draft'"
                            groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                    <button name="action_hand_over_to_transport" type="object" string="Hand over to transport"
                            class="btn-primary" invisible="state != 'issued'"
                            groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                    <button name="action_cancel" type="object" string="Cancel slip"
                            invisible="state in ('cancelled',)" context="{'itr_reason': 'Cancelled from form'}"
                            groups="itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                    <field name="state" widget="statusbar" statusbar_visible="draft,issued,handed_over"/>
                </header>
                <sheet>
                    <div class="oe_title"><h1><field name="name" readonly="1"/></h1></div>
                    <group>
                        <group>
                            <field name="case_id" readonly="state != 'draft'"/>
                            <field name="customer_id" readonly="state != 'draft'"/>
                            <field name="slip_date" readonly="state != 'draft'"/>
                            <field name="company_id" groups="base.group_multi_company"/>
                        </group>
                        <group>
                            <field name="delivery_mode" readonly="state != 'draft'"/>
                            <field name="destination" readonly="state != 'draft'"/>
                            <field name="border_id" readonly="state != 'draft'"/>
                            <field name="dispatch_count" readonly="state == 'cancelled'"/>
                            <field name="current_owner_id" readonly="1"/>
                            <field name="owner_deadline" readonly="1"/>
                        </group>
                    </group>
                    <notebook>
                        <page string="Lines" name="lines">
                            <field name="line_ids" readonly="state != 'draft'">
                                <list editable="bottom">
                                    <field name="sequence" widget="handle"/>
                                    <field name="case_id" column_invisible="1"/>
                                    <field name="case_item_id" domain="[('case_id', '=', parent.case_id)]"/>
                                    <field name="goods_description"/>
                                    <field name="allocated_tonnage"/>
                                    <field name="sale_price_unit"/>
                                    <field name="currency_id"/>
                                    <field name="sale_amount" readonly="1"/>
                                    <field name="base_amount" readonly="1"/>
                                    <field name="rate_locked" readonly="1"/>
                                </list>
                            </field>
                            <group>
                                <field name="total_tonnage" readonly="1"/>
                                <field name="total_sale_base" readonly="1"/>
                            </group>
                        </page>
                        <page string="History" name="history">
                            <group>
                                <group>
                                    <field name="issued_by_id" readonly="1"/>
                                    <field name="issued_on" readonly="1"/>
                                </group>
                                <group>
                                    <field name="handed_over_by_id" readonly="1"/>
                                    <field name="handed_over_on" readonly="1"/>
                                    <field name="cancel_reason" readonly="1"/>
                                </group>
                            </group>
                            <field name="note"/>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_sales_slip_list" model="ir.ui.view">
        <field name="name">itr.sales.slip.list</field>
        <field name="model">itr.sales.slip</field>
        <field name="arch" type="xml">
            <list string="Sales Slips">
                <field name="name"/>
                <field name="case_id"/>
                <field name="customer_id"/>
                <field name="slip_date"/>
                <field name="total_tonnage"/>
                <field name="total_sale_base"/>
                <field name="current_owner_id"/>
                <field name="state" widget="badge"
                       decoration-info="state == 'draft'"
                       decoration-warning="state == 'issued'"
                       decoration-success="state == 'handed_over'"
                       decoration-danger="state == 'cancelled'"/>
            </list>
        </field>
    </record>

    <record id="view_itr_sales_slip_search" model="ir.ui.view">
        <field name="name">itr.sales.slip.search</field>
        <field name="model">itr.sales.slip</field>
        <field name="arch" type="xml">
            <search string="Sales Slips">
                <field name="name"/>
                <field name="case_id"/>
                <field name="customer_id"/>
                <filter name="my_slips" string="My slips" domain="[('current_owner_id', '=', uid)]"/>
                <filter name="open_slips" string="Open" domain="[('state', 'in', ('draft', 'issued'))]"/>
                <filter name="group_case" string="Trade case" context="{'group_by': 'case_id'}"/>
                <filter name="group_state" string="State" context="{'group_by': 'state'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_sales_slip" model="ir.actions.act_window">
        <field name="name">Sales Slips</field>
        <field name="res_model">itr.sales.slip</field>
        <field name="view_mode">list,form</field>
        <field name="context">{'search_default_open_slips': 1}</field>
    </record>

    <!-- smart buttons on the phase-4 trade case form (view inheritance, no rewrite) -->
    <record id="view_itr_trade_case_form_phase5" model="ir.ui.view">
        <field name="name">itr.trade.case.form.phase5</field>
        <field name="model">itr.trade.case</field>
        <field name="inherit_id" ref="itr_core.view_itr_trade_case_form"/>
        <field name="arch" type="xml">
            <xpath expr="//header/field[@name='state']" position="before">
                <button name="action_new_sales_slip" type="object" string="New sales slip"
                        invisible="state not in ('approved', 'slips_issued')"
                        groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
            </xpath>
            <xpath expr="//sheet/div[@class='oe_title']" position="before">
                <div class="oe_button_box" name="button_box">
                    <button name="action_open_sales_slips" type="object" class="oe_stat_button" icon="fa-file-text-o">
                        <field name="sales_slip_count" widget="statinfo" string="Sales slips"/>
                    </button>
                </div>
            </xpath>
            <xpath expr="//field[@name='total_contract_tonnage']" position="after">
                <field name="reserved_tonnage_total" readonly="1"/>
            </xpath>
            <xpath expr="//field[@name='item_ids']/list/field[@name='reserved_tonnage']" position="before">
                <field name="allocated_tonnage" readonly="1"/>
            </xpath>
        </field>
    </record>
</odoo>
XMLEOF

write_utf8 "${CORE_DIR}/views/itr_work_assignment_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_work_assignment_log_list" model="ir.ui.view">
        <field name="name">itr.work.assignment.log.list</field>
        <field name="model">itr.work.assignment.log</field>
        <field name="arch" type="xml">
            <list string="Work Assignment Log" create="false" edit="false" delete="false">
                <field name="assigned_on"/>
                <field name="res_model"/>
                <field name="record_display"/>
                <field name="from_user_id"/>
                <field name="to_user_id"/>
                <field name="assigned_by_id"/>
                <field name="state_at_assignment"/>
                <field name="reason"/>
            </list>
        </field>
    </record>
    <record id="action_itr_work_assignment_log" model="ir.actions.act_window">
        <field name="name">Work Assignment Log</field>
        <field name="res_model">itr.work.assignment.log</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${CORE_DIR}/views/itr_core_phase5_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_sales_slip"
              name="Sales Slips"
              parent="itr_core.menu_itr_trade_root"
              action="action_itr_sales_slip"
              sequence="15"/>
    <menuitem id="menu_itr_work_assignment_log"
              name="Work Assignment Log"
              parent="itr_core.menu_itr_trade_root"
              action="action_itr_work_assignment_log"
              sequence="35"/>
</odoo>
XMLEOF

# ------------------------------------------------------------------ tests --
write_utf8 "${CORE_DIR}/tests/test_sales_slip_phase5.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 5 automated tests of itr_core (Q04/G01: real seeded users only).

Positive: three slips for one goods row within the cap; issuing moves the
case to slips_issued; reserved tonnage roll-up. Negative: transport user
cannot create a slip (RPC), slip before signature refused, tonnage above the
cap refused, [FIX-P3-1] Iranian plate/national id really validated,
[FIX-P4-2] frozen goods row after signature.
"""
import base64

from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged

from .common import ItrCoreCase


@tagged("post_install", "-at_install", "itr_core")
class TestItrSalesSlipPhase5(ItrCoreCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Users = cls.env["res.users"]

        def real(login):
            user = Users.search([("login", "=", login)], limit=1)
            assert user, "seeded phase-3 user missing: %s" % login
            return user

        cls.ceo = real("hadi.karamian@irbco.local")
        cls.fin_user = real("faezeh.heydari@irbco.local")
        cls.fin_sup = real("ehsan.nahalparvar@irbco.local")
        cls.legal = real("pouya.soleimani@irbco.local")
        cls.treasury = real("atieh.alaei@irbco.local")
        cls.receivables = real("zahra.mirzaei@irbco.local")
        cls.transport_docs = real("mohaddeseh.enayati@irbco.local")
        cls.transport_sup = real("najmeh.afrashtehpour@irbco.local")
        cls.Case = cls.env["itr.trade.case"].with_context(itr_notify_sync=True)
        cls.Slip = cls.env["itr.sales.slip"].with_context(itr_notify_sync=True)
        cls.buyer = cls.env["res.partner"].sudo().create({"name": "TEST buyer P5", "is_company": True})

    # ------------------------------------------------------------- helpers
    def _case(self, tonnage=100.0):
        return self.Case.with_user(self.fin_user).create({
            "requested_by": self.ceo.id,
            "deal_pattern": "buy_first",
            "item_ids": [(0, 0, {
                "name": "TEST coil P5", "row_kind": "both", "thickness_mm": 2.0,
                "contract_tonnage": tonnage, "purchase_price_unit": 100.0,
                "sale_price_unit": 120.0,
            })],
        })

    def _signed_case(self, tonnage=100.0):
        case = self._case(tonnage)
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_approve()
        case.with_user(self.treasury).action_treasury_approve()
        case.with_user(self.receivables).action_receivables_approve()
        case.with_context(itr_trade_state_engine=True).write({
            "signed_document": base64.b64encode(b"TEST signed"),
            "signed_document_filename": "signed.pdf",
        })
        case.with_user(self.fin_sup).action_confirm_signed()
        self.assertEqual(case.state, "approved")
        return case

    def _slip(self, case, tonnage, user=None):
        return self.Slip.with_user(user or self.fin_user).create({
            "case_id": case.id,
            "customer_id": self.buyer.id,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": tonnage})],
        })

    # ------------------------------------------------------------ positive
    def test_10_three_slips_for_one_row_within_cap(self):
        case = self._signed_case(100.0)
        s1 = self._slip(case, 30.0)
        s2 = self._slip(case, 30.0)
        s3 = self._slip(case, 40.0)
        self.assertTrue(s1.name.startswith("SS/"))
        s1.with_user(self.fin_user).action_issue()
        self.assertEqual(case.state, "slips_issued", "first issued slip moves the case")
        self.assertTrue(all(s1.line_ids.mapped("rate_locked")), "FIN-014: each event locks its rate")
        s2.with_user(self.fin_sup).action_issue()      # supervisor may issue too (5.1)
        s3.with_user(self.ceo).action_issue()          # CEO may issue too (5.1)
        item = case.item_ids[0]
        self.assertAlmostEqual(item.reserved_tonnage, 100.0, "reserved = issued allocations")
        self.assertAlmostEqual(item.allocated_tonnage, 100.0)
        self.assertEqual(case.sales_slip_count, 3)

    def test_11_cancel_releases_reservation(self):
        case = self._signed_case(50.0)
        slip = self._slip(case, 50.0)
        slip.with_user(self.fin_user).action_issue()
        self.assertAlmostEqual(case.item_ids[0].reserved_tonnage, 50.0)
        slip.with_user(self.fin_sup).action_cancel(reason="TEST cancel")
        self.assertEqual(slip.state, "cancelled")
        self.assertAlmostEqual(case.item_ids[0].reserved_tonnage, 0.0)

    def test_12_receive_by_transport_is_the_only_door(self):
        """5.4 contract: the hook exists on the slip and never creates an invoice."""
        case = self._signed_case(20.0)
        slip = self._slip(case, 20.0)
        self.assertTrue(hasattr(slip, "receive_by_transport"))
        self.assertTrue(hasattr(slip, "_create_transport_cases"), "hook implemented by itr_transport")
        # FIN-016: no accounting document is ever created by the slip
        self.assertNotIn("account", [d.name for d in self.env["ir.module.module"].sudo().search(
            [("name", "=", "itr_core")], limit=1).dependencies_id])

    # ------------------------------------------------------------ negative
    def test_20_transport_user_cannot_create_slip_by_rpc(self):
        case = self._signed_case(10.0)
        # Odoo 19 assertRaises() does not accept a tuple of exception classes
        # (TypeError: issubclass() arg 1 must be a class). AccessError is the
        # expected ACL refusal; UserError is the server-side issuer-role guard.
        try:
            self._slip(case, 10.0, user=self.transport_docs)
            self.fail("transport docs user must not create a sales slip")
        except (AccessError, UserError):
            pass
        try:
            self._slip(case, 10.0, user=self.transport_sup)
            self.fail("transport supervisor must not create a sales slip")
        except (AccessError, UserError):
            pass

    def test_21_slip_before_signature_refused_even_for_superuser(self):
        case = self._case(10.0)
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_approve()
        case.with_user(self.treasury).action_treasury_approve()
        case.with_user(self.receivables).action_receivables_approve()
        self.assertEqual(case.state, "pending_signature")
        with self.assertRaises(UserError):
            self._slip(case, 10.0)
        with self.assertRaises(UserError):
            self.Slip.sudo().create({
                "case_id": case.id, "customer_id": self.buyer.id,
                "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": 1.0})],
            })

    def test_22_tonnage_above_cap_refused(self):
        case = self._signed_case(100.0)
        self._slip(case, 70.0)
        with self.assertRaises(ValidationError):
            self._slip(case, 40.0)

    def test_23_row_frozen_after_review_chain(self):
        """[FIX-P4-2] FIN-014 is enforced on the server, not only in the UI."""
        case = self._signed_case(10.0)
        with self.assertRaises(UserError):
            case.item_ids.with_user(self.fin_user).write({"contract_tonnage": 999.0})
        with self.assertRaises(UserError):
            case.item_ids.with_user(self.fin_user).write({"reserved_tonnage": 5.0})

    def test_24_guarded_layer_really_validates_iranian_aliases(self):
        """[FIX-P3-1] 'iranian' is now recognised as Iranian by the guarded layer."""
        service = self.env["itr.validation.service"].with_user(self.transport_docs)
        with self.assertRaises(ValidationError):
            service.check_national_id("1111111111", nationality="iranian")
        with self.assertRaises(ValidationError):
            service.check_plate("TR 34 ABC 12", plate_type="iranian")
        self.assertEqual(service.check_plate("TR 34 ABC 12", plate_type="transit"), "TR 34 ABC 12")
        with self.assertRaises(ValidationError):
            self.env["itr.vehicle"].with_user(self.transport_docs).create({
                "plate_number": "TR 34 ABC 12", "plate_type": "iranian"})

    def test_25_no_crm_dependency(self):
        """BR-051 / X16: 'CRM' is the hand-over hook, never a module."""
        module = self.env["ir.module.module"].sudo().search([("name", "=", "crm")], limit=1)
        self.assertTrue(not module or module.state != "installed")
        for name in ("itr_base", "itr_notify", "itr_core"):
            mod = self.env["ir.module.module"].sudo().search([("name", "=", name)], limit=1)
            self.assertNotIn("crm", mod.dependencies_id.mapped("name"))
PYEOF

# =============================================================================
step "4) ماژول جدید itr_transport (اسکلت فاز ۵؛ فاز ۶ با _inherit گسترش می‌دهد)"
# =============================================================================
mkdir -p "${TRN_DIR}"/{models,security,data,views,i18n,tests}
find "${TRN_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

write_utf8 "${TRN_DIR}/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import models
PYEOF

write_utf8 "${TRN_DIR}/__manifest__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
{
    "name": "ITR Transport",
    "summary": "Transport / loading cases: N:1 to the sales slip, idempotent auto-creation, field operations (phase 5 skeleton, phase 6 operations)",
    "description": """
ITR Transport (Phase 5 skeleton -> Phase 6 operations)
======================================================
* itr.transport.case: one record per truck / loading, ALWAYS N:1 to the sales
  slip and the trade case (BR-002, never unique).
* Created ONLY through itr.sales.slip.receive_by_transport() (checklist 5.4)
  with a real database idempotency key (sales_slip_id, dispatch_no) and a
  transactional row lock (checklist 5.5).
* Complete snapshot of the commercial data with source references (BR-052);
  the invoice number of every loading comes from ITS OWN sales slip (BR-055).
* The 13 state names of SRS 7-5 are locked here (G10) - phase 6 only extends
  the transition table by inheritance, never renames.
* Cartable contract of phase 4/5 (itr.cartable.mixin) - no second task engine.
""",
    "version": "19.0.1.0.0",
    "category": "Localization/Iran",
    "author": "Iran Trade & Transport ERP",
    "maintainer": "Iran Trade & Transport ERP",
    "license": "LGPL-3",
    "depends": ["base", "mail", "itr_base", "itr_notify", "itr_core"],
    "data": [
        "security/ir.model.access.csv",
        "security/itr_transport_rules.xml",
        "data/itr_transport_data.xml",
        "data/itr_transport_notify_events.xml",
        "views/itr_transport_case_views.xml",
        "views/itr_sales_slip_transport_views.xml",
        "views/itr_transport_menus.xml",
    ],
    "installable": True,
    "application": False,
    "auto_install": False,
}
PYEOF

write_utf8 "${TRN_DIR}/models/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import itr_transport_case
from . import itr_sales_slip_transport
PYEOF

write_utf8 "${TRN_DIR}/models/itr_transport_case.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Transport case - phase 5 skeleton (checklist 5.5 .. 5.8 / SRS 7-5, BR-002).

LOCKED state names (G10 / Q11 - registered in ARCHITECTURE_DECISIONS.md):

    draft | pending_review | loading_authorized | loaded | in_transit |
    waiting_weighbridge | waiting_bijak | waiting_clearance | waiting_payment |
    delivered | settled | closed | cancelled

Phase 5 only uses draft -> pending_review (-> cancelled). Phase 6 EXTENDS the
transition table through _transition_table() by inheritance and adds the
operational tabs; this file is never rewritten (concern C2).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

TRANSPORT_STATES = [
    ("draft", "Draft"),
    ("pending_review", "Pending supervisor review"),
    ("loading_authorized", "Loading authorised"),
    ("loaded", "Loaded"),
    ("in_transit", "In transit"),
    ("waiting_weighbridge", "Waiting for weighbridge"),
    ("waiting_bijak", "Waiting for bijak"),
    ("waiting_clearance", "Waiting for clearance"),
    ("waiting_payment", "Waiting for payment"),
    ("delivered", "Delivered"),
    ("settled", "Settled"),
    ("closed", "Closed"),
    ("cancelled", "Cancelled"),
]

TRANSPORT_ENGINE_CTX = "itr_transport_state_engine"
FROM_SLIP_CTX = "itr_transport_from_slip"

DELIVERY_MODES = [
    ("factory_to_customer", "Factory door to customer address"),
    ("factory_to_border", "Factory door to exit border"),
    ("other", "Other (see notes)"),
]


class ItrTransportCase(models.Model):
    _name = "itr.transport.case"
    _description = "Transport Case"
    _inherit = ["mail.thread", "mail.activity.mixin", "itr.cartable.mixin"]
    _order = "id desc"

    # ------------------------------------------------------------ identity
    name = fields.Char(string="Transport case number", required=True, copy=False,
                       readonly=True, index=True, default=lambda self: _("New"))
    company_id = fields.Many2one("res.company", string="Company", required=True, index=True,
                                 default=lambda self: self.env.company)
    state = fields.Selection(TRANSPORT_STATES, string="State", required=True, default="draft",
                             index=True, tracking=True, copy=False)
    active = fields.Boolean(string="Active", default=True)

    # ------------------------------------------- N:1 links (never unique)
    trade_case_id = fields.Many2one("itr.trade.case", string="Trade case", required=True,
                                    ondelete="restrict", index=True)
    sales_slip_id = fields.Many2one("itr.sales.slip", string="Sales slip", required=True,
                                    ondelete="restrict", index=True)
    source_item_id = fields.Many2one(
        "itr.trade.case.item", string="Goods row (source)", ondelete="restrict", index=True,
        help="Set automatically for single-line slips; the transport supervisor sets it "
             "for multi-line slips before the weighbridge confirmation (OPS-023).")
    dispatch_no = fields.Integer(string="Dispatch no.", required=True, default=1,
                                 help="Sequential loading number inside its sales slip - "
                                      "part of the idempotency key (checklist 5.5).")

    # 5.5: a REAL database idempotency key (ADR-022: models.Constraint only)
    _slip_dispatch_uniq = models.Constraint(
        "unique(sales_slip_id, dispatch_no)",
        "This loading number already exists for this sales slip (idempotency key, checklist 5.5).",
    )

    # ------------------------------------- 5.6 snapshot (BR-052 / BR-055)
    purchase_ref = fields.Char(string="Purchase reference (snapshot)", readonly=True)
    sales_ref = fields.Char(string="Sales invoice number (snapshot)", readonly=True,
                            help="BR-055: comes from the OWN sales slip of this loading, never from the case header.")
    order_date = fields.Date(string="Order date (snapshot)", readonly=True)
    factory_id = fields.Many2one("res.partner", string="Factory / origin (snapshot)", readonly=True)
    customer_id = fields.Many2one("res.partner", string="Customer (snapshot)", readonly=True)
    goods_description = fields.Char(string="Goods description (snapshot)", readonly=True)
    thickness_mm = fields.Float(string="Thickness (mm)", readonly=True)
    width_cm = fields.Float(string="Width (cm)", readonly=True)
    length_cm = fields.Float(string="Length (cm)", readonly=True)
    dimension_note = fields.Char(string="Dimension note", readonly=True)
    planned_tonnage = fields.Float(string="Planned tonnage", help="Tonnage planned for this truck.")
    purchase_amount_base = fields.Float(string="Purchase amount (IRR, snapshot)", readonly=True)
    sale_amount_base = fields.Float(string="Sale amount (IRR, snapshot)", readonly=True)
    destination = fields.Char(string="Destination (snapshot)", readonly=True)
    border_id = fields.Many2one("itr.border", string="Exit border (snapshot)", readonly=True)
    delivery_mode = fields.Selection(DELIVERY_MODES, string="Delivery mode (snapshot)", readonly=True)
    snapshot_on = fields.Datetime(string="Snapshot taken on", readonly=True)
    cancel_reason = fields.Text(string="Cancellation reason", readonly=True, copy=False)
    note = fields.Text(string="Notes")

    # ================================================================ engine
    def _transition_table(self):
        """Phase 5 table; phase 6 extends it by inheritance (never renames)."""
        return {
            "draft": {"pending_review", "cancelled"},
            "pending_review": {"cancelled"},
            "cancelled": set(),
            "closed": set(),
        }

    def _do_transition(self, new_state):
        for record in self:
            allowed = record._transition_table().get(record.state, set())
            if new_state not in allowed:
                raise UserError(
                    _("Illegal state change: %(old)s -> %(new)s is not in the official "
                      "transition table of the transport case.", old=record.state, new=new_state))
            record.with_context(**{TRANSPORT_ENGINE_CTX: True}).write({"state": new_state})
            record.message_post(body=_(
                "State changed to <b>%(state)s</b> by %(user)s.",
                state=dict(TRANSPORT_STATES).get(new_state, new_state),
                user=self.env.user.display_name))
        return True

    def _require_group(self, xmlids, action_label):
        if self.env.su:
            raise UserError(_("Business transitions are never executed as superuser (G01/Q03)."))
        if isinstance(xmlids, str):
            xmlids = (xmlids,)
        if not any(self.env.user.has_group(x) for x in xmlids):
            raise UserError(
                _("Access refused: the action '%(action)s' requires one of the roles %(groups)s.",
                  action=action_label, groups=", ".join(xmlids)))

    @api.model_create_multi
    def create(self, vals_list):
        from_slip = self.env.context.get(FROM_SLIP_CTX)
        if not from_slip and not self.env.user.has_group("itr_core.group_transport_supervisor"):
            raise UserError(
                _("A transport case is created automatically from a sales slip "
                  "(checklist 5.5); manual creation is reserved to the transport supervisor."))
        for vals in vals_list:
            if vals.get("state") and vals["state"] != "draft":
                raise UserError(_("A transport case always starts in draft."))
            if not vals.get("name") or vals.get("name") == _("New"):
                vals["name"] = self.env["ir.sequence"].next_by_code("itr.transport.case") or _("New")
            vals.setdefault("snapshot_on", fields.Datetime.now())
        records = super().create(vals_list)
        for record in records:
            if record.sales_slip_id.case_id != record.trade_case_id:
                raise UserError(_("The sales slip must belong to the trade case of the loading."))
        return records

    def write(self, vals):
        if "state" in vals and not self.env.context.get(TRANSPORT_ENGINE_CTX):
            raise UserError(
                _("The transport case state can only change through its official actions."))
        for field_name in ("sales_slip_id", "trade_case_id", "dispatch_no"):
            if field_name in vals:
                for record in self:
                    if record[field_name] and vals[field_name] != (
                            record[field_name].id if hasattr(record[field_name], "id") else record[field_name]):
                        raise UserError(_("The source links of a transport case are frozen (BR-052)."))
        return super().write(vals)

    def unlink(self):
        for record in self:
            if record.state != "draft":
                raise UserError(_("Only a draft transport case can be deleted (OPS-027)."))
        return super().unlink()

    # ================================================================ actions
    def action_cancel(self, reason=None):
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        self._require_group(("itr_core.group_transport_supervisor", "itr_core.group_finance_supervisor",
                             "itr_core.group_ceo"), "cancel transport case")
        if not reason:
            raise UserError(_("Cancelling a transport case requires a mandatory reason (OPS-027)."))
        for record in self:
            record.with_context(**{TRANSPORT_ENGINE_CTX: True}).write({"cancel_reason": reason})
            record._do_transition("cancelled")
            record.with_context(itr_cartable_engine=True).write({"current_owner_id": False})
        return True

    def action_open_sales_slip(self):
        self.ensure_one()
        return {"type": "ir.actions.act_window", "res_model": "itr.sales.slip",
                "res_id": self.sales_slip_id.id, "view_mode": "form", "target": "current"}
PYEOF

write_utf8 "${TRN_DIR}/models/itr_sales_slip_transport.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Implementation of the phase-5 hand-over hook (checklist 5.4 .. 5.8).

itr_core defines receive_by_transport(); this module implements
_create_transport_cases() by inheritance so the dependency direction of Q02
stays one-way (itr_transport -> itr_core, never the opposite).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError

from .itr_transport_case import FROM_SLIP_CTX, TRANSPORT_ENGINE_CTX


class ItrSalesSlip(models.Model):
    _inherit = "itr.sales.slip"

    transport_case_ids = fields.One2many("itr.transport.case", "sales_slip_id",
                                         string="Transport cases")
    transport_case_count = fields.Integer(string="Transport cases",
                                          compute="_compute_transport_case_count")

    @api.depends("transport_case_ids.state")
    def _compute_transport_case_count(self):
        for slip in self:
            slip.transport_case_count = len(
                slip.transport_case_ids.filtered(lambda t: t.state != "cancelled"))

    def _has_active_transport(self):
        self.ensure_one()
        return bool(self.transport_case_ids.filtered(lambda t: t.state != "cancelled"))

    def _transport_snapshot_vals(self, dispatch_no, per_truck_tonnage):
        """5.6 / BR-052: everything the field needs, with source references."""
        self.ensure_one()
        case = self.case_id
        lines = self.line_ids
        single = lines[:1] if len(lines) == 1 else lines.browse()
        item = single.case_item_id if single else self.env["itr.trade.case.item"]
        engine = self.env["itr.money.engine"]
        purchase_base = 0.0
        if item:
            share = (per_truck_tonnage / item.contract_tonnage) if item.contract_tonnage else 0.0
            purchase_base = engine.item_side_base(item, "purchase") * share
        sale_base = (self.total_sale_base / self.total_tonnage * per_truck_tonnage) if self.total_tonnage else 0.0
        purchase_ref = case.name
        if case.proforma_purchase_ref:
            purchase_ref = "%s / %s" % (case.name, case.proforma_purchase_ref)
        return {
            "trade_case_id": case.id,
            "sales_slip_id": self.id,
            "source_item_id": item.id if item else False,
            "dispatch_no": dispatch_no,
            "company_id": self.company_id.id,
            # BR-055: the invoice number of the loading is ITS OWN slip number
            "purchase_ref": purchase_ref,
            "sales_ref": self.name,
            "order_date": self.slip_date,
            "factory_id": case.factory_id.id,
            "customer_id": self.customer_id.id,
            "goods_description": "; ".join(lines.mapped("case_item_id.name")),
            "thickness_mm": item.thickness_mm if item else 0.0,
            "width_cm": item.width_cm if item else 0.0,
            "length_cm": item.length_cm if item else 0.0,
            "dimension_note": item.dimension_note if item else False,
            "planned_tonnage": per_truck_tonnage,
            "purchase_amount_base": purchase_base,
            "sale_amount_base": sale_base,
            "destination": self.destination or case.destination,
            "border_id": (self.border_id or case.border_id).id,
            "delivery_mode": self.delivery_mode,
        }

    def _create_transport_cases(self, dispatch_count=None):
        """5.5: idempotent, transactionally locked creation (never a duplicate)."""
        self.ensure_one()
        Transport = self.env["itr.transport.case"]
        count = int(dispatch_count or self.dispatch_count or 1)
        if count < 1:
            raise UserError(_("At least one loading must be requested."))
        # transactional lock on the slip row: two concurrent hand-overs serialise
        self.env.flush_all()
        self.env.cr.execute("SELECT id FROM itr_sales_slip WHERE id = %s FOR UPDATE", (self.id,))
        existing = Transport.with_context(active_test=False).search([("sales_slip_id", "=", self.id)])
        have = set(existing.mapped("dispatch_no"))
        per_truck = (self.total_tonnage / count) if count else 0.0
        created = Transport
        for dispatch_no in range(1, count + 1):
            if dispatch_no in have:
                continue  # idempotent: already created by a previous run
            vals = self._transport_snapshot_vals(dispatch_no, round(per_truck, 3))
            record = Transport.with_context(**{FROM_SLIP_CTX: True}).create(vals)
            record._do_transition("pending_review")
            created |= record
        for record in created:
            record._hand_over_to_group("itr_core.group_transport_supervisor",
                                       _("New loading waiting for loading authorisation"))
            record._itr_notify("transport.case_created")
        return created

    def action_open_transport_cases(self):
        self.ensure_one()
        return {
            "type": "ir.actions.act_window",
            "name": _("Transport cases"),
            "res_model": "itr.transport.case",
            "view_mode": "list,form",
            "domain": [("sales_slip_id", "=", self.id)],
        }
PYEOF

write_utf8 "${TRN_DIR}/security/ir.model.access.csv" <<'CSVEOF'
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_itr_transport_case_user,itr.transport.case user read,model_itr_transport_case,base.group_user,1,0,0,0
access_itr_transport_case_trn_sup,itr.transport.case transport supervisor,model_itr_transport_case,itr_core.group_transport_supervisor,1,1,1,0
access_itr_transport_case_docs,itr.transport.case docs,model_itr_transport_case,itr_core.group_transport_docs,1,1,0,0
access_itr_transport_case_customs,itr.transport.case customs,model_itr_transport_case,itr_core.group_customs_officer,1,1,0,0
access_itr_transport_case_delivery,itr.transport.case delivery,model_itr_transport_case,itr_core.group_transport_delivery,1,1,0,0
access_itr_transport_case_receivables,itr.transport.case receivables,model_itr_transport_case,itr_core.group_receivables_user,1,1,0,0
access_itr_transport_case_fin_user,itr.transport.case fin user (slip hand-over path),model_itr_transport_case,itr_core.group_finance_user,1,1,1,0
access_itr_transport_case_fin_sup,itr.transport.case fin sup,model_itr_transport_case,itr_core.group_finance_supervisor,1,1,1,0
access_itr_transport_case_fin_mgr,itr.transport.case fin mgr,model_itr_transport_case,itr_core.group_financial_manager,1,1,0,0
access_itr_transport_case_ceo,itr.transport.case ceo,model_itr_transport_case,itr_core.group_ceo,1,1,1,0
access_itr_transport_case_auditor,itr.transport.case auditor,model_itr_transport_case,itr_core.group_auditor,1,0,0,0
CSVEOF

write_utf8 "${TRN_DIR}/security/itr_transport_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">
        <record id="rule_itr_transport_case_company" model="ir.rule">
            <field name="name">Transport case: company rule</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_case"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/data/itr_transport_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="seq_itr_transport_case" model="ir.sequence">
            <field name="name">Transport Case</field>
            <field name="code">itr.transport.case</field>
            <field name="prefix">TR/%(range_year)s/</field>
            <field name="padding">5</field>
            <field name="company_id" eval="False"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/data/itr_transport_notify_events.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="event_transport_case_created" model="itr.notification.event">
            <field name="event_key">transport.case_created</field>
            <field name="title">Transport case created from a sales slip</field>
            <field name="category">transport</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">current_owner_id</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor'))]"/>
            <field name="internal_subject">New transport case {{name}}</field>
            <field name="internal_body">Transport case {{name}} was created automatically from sales slip {{sales_ref}} and waits for loading authorisation.</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/views/itr_transport_case_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_transport_case_form" model="ir.ui.view">
        <field name="name">itr.transport.case.form</field>
        <field name="model">itr.transport.case</field>
        <field name="arch" type="xml">
            <form string="Transport Case">
                <header>
                    <button name="action_cancel" type="object" string="Cancel loading"
                            invisible="state in ('closed', 'cancelled')"
                            context="{'itr_reason': 'Cancelled from form'}"
                            groups="itr_core.group_transport_supervisor,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                    <field name="state" widget="statusbar"
                           statusbar_visible="pending_review,loading_authorized,loaded,in_transit,delivered,settled,closed"/>
                </header>
                <sheet>
                    <div class="oe_button_box" name="button_box">
                        <button name="action_open_sales_slip" type="object" class="oe_stat_button" icon="fa-file-text-o" string="Sales slip"/>
                    </div>
                    <div class="oe_title"><h1><field name="name" readonly="1"/></h1></div>
                    <notebook>
                        <page string="Commercial snapshot" name="snapshot">
                            <group>
                                <group string="Source (frozen, BR-052)">
                                    <field name="trade_case_id" readonly="1"/>
                                    <field name="sales_slip_id" readonly="1"/>
                                    <field name="dispatch_no" readonly="1"/>
                                    <field name="source_item_id"
                                           readonly="state not in ('draft', 'pending_review', 'loading_authorized', 'loaded', 'in_transit')"
                                           domain="[('case_id', '=', trade_case_id)]"/>
                                    <field name="company_id" groups="base.group_multi_company"/>
                                </group>
                                <group string="Cartable">
                                    <field name="current_owner_id" readonly="1"/>
                                    <field name="owner_deadline" readonly="1"/>
                                    <field name="snapshot_on" readonly="1"/>
                                </group>
                            </group>
                            <group>
                                <group string="References">
                                    <field name="purchase_ref"/>
                                    <field name="sales_ref"/>
                                    <field name="order_date"/>
                                    <field name="factory_id"/>
                                    <field name="customer_id"/>
                                </group>
                                <group string="Goods and route">
                                    <field name="goods_description"/>
                                    <field name="thickness_mm"/>
                                    <field name="width_cm"/>
                                    <field name="length_cm"/>
                                    <field name="planned_tonnage"/>
                                    <field name="destination"/>
                                    <field name="border_id"/>
                                    <field name="delivery_mode"/>
                                </group>
                            </group>
                            <group string="Amounts (snapshot)">
                                <field name="purchase_amount_base"/>
                                <field name="sale_amount_base"/>
                            </group>
                            <field name="cancel_reason" readonly="1" invisible="not cancel_reason"/>
                            <field name="note"/>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_transport_case_list" model="ir.ui.view">
        <field name="name">itr.transport.case.list</field>
        <field name="model">itr.transport.case</field>
        <field name="arch" type="xml">
            <list string="Transport Cases">
                <field name="name"/>
                <field name="trade_case_id"/>
                <field name="sales_slip_id"/>
                <field name="dispatch_no"/>
                <field name="customer_id"/>
                <field name="planned_tonnage"/>
                <field name="current_owner_id"/>
                <field name="state" widget="badge"
                       decoration-info="state in ('draft', 'pending_review')"
                       decoration-warning="state in ('loading_authorized', 'loaded', 'in_transit', 'waiting_weighbridge', 'waiting_bijak', 'waiting_clearance', 'waiting_payment')"
                       decoration-success="state in ('delivered', 'settled', 'closed')"
                       decoration-danger="state == 'cancelled'"/>
            </list>
        </field>
    </record>

    <record id="view_itr_transport_case_kanban" model="ir.ui.view">
        <field name="name">itr.transport.case.kanban</field>
        <field name="model">itr.transport.case</field>
        <field name="arch" type="xml">
            <kanban default_group_by="state" records_draggable="false" group_create="false">
                <field name="name"/>
                <field name="state"/>
                <field name="sales_ref"/>
                <field name="current_owner_id"/>
                <field name="planned_tonnage"/>
                <templates>
                    <t t-name="card">
                        <div class="oe_kanban_card oe_kanban_global_click">
                            <strong><field name="name"/></strong>
                            <div>Slip: <field name="sales_ref"/></div>
                            <div>Owner: <field name="current_owner_id"/></div>
                            <div>Planned: <field name="planned_tonnage"/> t</div>
                        </div>
                    </t>
                </templates>
            </kanban>
        </field>
    </record>

    <record id="view_itr_transport_case_search" model="ir.ui.view">
        <field name="name">itr.transport.case.search</field>
        <field name="model">itr.transport.case</field>
        <field name="arch" type="xml">
            <search string="Transport Cases">
                <field name="name"/>
                <field name="sales_ref"/>
                <field name="trade_case_id"/>
                <field name="customer_id"/>
                <filter name="my_loadings" string="My loadings" domain="[('current_owner_id', '=', uid)]"/>
                <filter name="open_loadings" string="Open" domain="[('state', 'not in', ('closed', 'cancelled'))]"/>
                <filter name="group_state" string="State" context="{'group_by': 'state'}"/>
                <filter name="group_slip" string="Sales slip" context="{'group_by': 'sales_slip_id'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_transport_case" model="ir.actions.act_window">
        <field name="name">Transport Cases</field>
        <field name="res_model">itr.transport.case</field>
        <field name="view_mode">kanban,list,form</field>
        <field name="context">{'search_default_open_loadings': 1}</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/views/itr_sales_slip_transport_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_sales_slip_form_transport" model="ir.ui.view">
        <field name="name">itr.sales.slip.form.transport</field>
        <field name="model">itr.sales.slip</field>
        <field name="inherit_id" ref="itr_core.view_itr_sales_slip_form"/>
        <field name="arch" type="xml">
            <xpath expr="//sheet/div[@class='oe_title']" position="before">
                <div class="oe_button_box" name="button_box">
                    <button name="action_open_transport_cases" type="object" class="oe_stat_button" icon="fa-truck">
                        <field name="transport_case_count" widget="statinfo" string="Transport cases"/>
                    </button>
                </div>
            </xpath>
        </field>
    </record>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/views/itr_transport_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_transport_root"
              name="Transport Operations"
              parent="itr_core.menu_itr_core_root"
              sequence="15"/>
    <menuitem id="menu_itr_transport_case"
              name="Transport Cases"
              parent="menu_itr_transport_root"
              action="action_itr_transport_case"
              sequence="10"/>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/i18n/fa_IR.po" <<'POEOF'
# Translation of Odoo Server - module itr_transport.
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

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_transport_case
msgid "Transport Case"
msgstr "پروندهٔ حمل"

#. module: itr_transport
#: model:ir.ui.menu,name:itr_transport.menu_itr_transport_root
msgid "Transport Operations"
msgstr "عملیات حمل"

#. module: itr_transport
#: model:ir.actions.act_window,name:itr_transport.action_itr_transport_case
#: model:ir.ui.menu,name:itr_transport.menu_itr_transport_case
msgid "Transport Cases"
msgstr "پرونده‌های حمل"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__draft
msgid "Draft"
msgstr "پیش‌نویس"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__pending_review
msgid "Pending supervisor review"
msgstr "در انتظار بررسی سرپرست حمل"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__loading_authorized
msgid "Loading authorised"
msgstr "مجوز بارگیری صادر شد"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__loaded
msgid "Loaded"
msgstr "بارگیری‌شده"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__in_transit
msgid "In transit"
msgstr "در مسیر"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__waiting_weighbridge
msgid "Waiting for weighbridge"
msgstr "در انتظار باسکول"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__waiting_bijak
msgid "Waiting for bijak"
msgstr "در انتظار بیجک"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__waiting_clearance
msgid "Waiting for clearance"
msgstr "در انتظار ترخیص"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__waiting_payment
msgid "Waiting for payment"
msgstr "در انتظار پرداخت"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__delivered
msgid "Delivered"
msgstr "تحویل‌شده"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__settled
msgid "Settled"
msgstr "تسویه‌شده"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__closed
msgid "Closed"
msgstr "مختومه"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_transport_case__state__cancelled
msgid "Cancelled"
msgstr "لغوشده"

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case.py:0
#, python-format
msgid "A transport case is created automatically from a sales slip (checklist 5.5); manual creation is reserved to the transport supervisor."
msgstr "پروندهٔ حمل به‌صورت خودکار از ریزفاکتور فروش ساخته می‌شود (بند 5.5)؛ ساخت دستی فقط برای سرپرست حمل مجاز است."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case.py:0
#, python-format
msgid "The transport case state can only change through its official actions."
msgstr "وضعیت پروندهٔ حمل فقط از طریق اکشن‌های رسمی تغییر می‌کند."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case.py:0
#, python-format
msgid "Cancelling a transport case requires a mandatory reason (OPS-027)."
msgstr "لغو پروندهٔ حمل نیازمند ثبت دلیل اجباری است (OPS-027)."

#. module: itr_transport
#: model:ir.model.constraint,message:itr_transport.constraint_itr_transport_case__slip_dispatch_uniq
msgid "This loading number already exists for this sales slip (idempotency key, checklist 5.5)."
msgstr "این شمارهٔ اعزام برای این ریزفاکتور قبلاً ثبت شده است (کلید Idempotency، بند 5.5)."
POEOF
cp -f "${TRN_DIR}/i18n/fa_IR.po" "${TRN_DIR}/i18n/fa.po"

write_utf8 "${TRN_DIR}/tests/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import common
from . import test_transport_case_phase5
PYEOF

write_utf8 "${TRN_DIR}/tests/common.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Shared helper: builds a signed trade case + issued sales slip with the REAL
seeded users of phase 3 (G01: never Administrator)."""
import base64

from odoo.tests import TransactionCase


class ItrTransportCase(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Users = cls.env["res.users"]

        def real(login):
            user = Users.search([("login", "=", login)], limit=1)
            assert user, "seeded phase-3 user missing: %s" % login
            return user

        cls.ceo = real("hadi.karamian@irbco.local")
        cls.fin_user = real("faezeh.heydari@irbco.local")
        cls.fin_sup = real("ehsan.nahalparvar@irbco.local")
        cls.fin_mgr = real("fin.mgr@irbco.local")
        cls.legal = real("pouya.soleimani@irbco.local")
        cls.treasury = real("atieh.alaei@irbco.local")
        cls.receivables = real("zahra.mirzaei@irbco.local")
        cls.transport_sup = real("najmeh.afrashtehpour@irbco.local")
        cls.transport_docs = real("mohaddeseh.enayati@irbco.local")
        cls.customs = real("mohammadi@irbco.local")
        cls.delivery = real("amini@irbco.local")
        cls.Case = cls.env["itr.trade.case"].with_context(itr_notify_sync=True)
        cls.Slip = cls.env["itr.sales.slip"].with_context(itr_notify_sync=True)
        cls.Transport = cls.env["itr.transport.case"].with_context(itr_notify_sync=True)
        cls.buyer = cls.env["res.partner"].sudo().create({"name": "TEST buyer TRN", "is_company": True})
        cls.factory = cls.env["res.partner"].sudo().create(
            {"name": "TEST factory TRN", "is_company": True, "is_factory": True})

    def _signed_case(self, tonnage=100.0, purchase=100.0, sale=120.0):
        case = self.Case.with_user(self.fin_user).create({
            "requested_by": self.ceo.id,
            "deal_pattern": "buy_first",
            "factory_id": self.factory.id,
            "destination": "TEST destination",
            "item_ids": [(0, 0, {
                "name": "TEST coil TRN", "row_kind": "both", "thickness_mm": 2.0,
                "width_cm": 125.0, "contract_tonnage": tonnage,
                "purchase_price_unit": purchase, "sale_price_unit": sale,
            })],
        })
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_approve()
        case.with_user(self.treasury).action_treasury_approve()
        case.with_user(self.receivables).action_receivables_approve()
        case.with_context(itr_trade_state_engine=True).write({
            "signed_document": base64.b64encode(b"TEST signed"),
            "signed_document_filename": "signed.pdf",
        })
        case.with_user(self.fin_sup).action_confirm_signed()
        return case

    def _issued_slip(self, case, tonnage, dispatches=1):
        slip = self.Slip.with_user(self.fin_user).create({
            "case_id": case.id,
            "customer_id": self.buyer.id,
            "dispatch_count": dispatches,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": tonnage})],
        })
        slip.with_user(self.fin_user).action_issue()
        return slip

    def _handed_over(self, tonnage=100.0, dispatches=1):
        case = self._signed_case(tonnage)
        slip = self._issued_slip(case, tonnage, dispatches)
        slip.with_user(self.fin_user).action_hand_over_to_transport()
        return case, slip, slip.transport_case_ids.sorted("dispatch_no")
PYEOF

write_utf8 "${TRN_DIR}/tests/test_transport_case_phase5.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.exceptions import AccessError, UserError
from odoo.tests import tagged
from odoo.tools import mute_logger

from .common import ItrTransportCase


@tagged("post_install", "-at_install", "itr_transport")
class TestItrTransportCasePhase5(ItrTransportCase):

    # ------------------------------------------------------------ positive
    def test_10_handover_creates_cases_in_supervisor_cartable(self):
        case, slip, cases = self._handed_over(90.0, dispatches=3)
        self.assertEqual(slip.state, "handed_over")
        self.assertEqual(len(cases), 3, "5.8: one slip -> N transport cases")
        self.assertEqual(sorted(cases.mapped("dispatch_no")), [1, 2, 3])
        self.assertTrue(all(c.name.startswith("TR/") for c in cases))
        self.assertTrue(all(c.state == "pending_review" for c in cases))
        owners = cases.mapped("current_owner_id")
        self.assertTrue(owners)
        self.assertTrue(all(u.has_group("itr_core.group_transport_supervisor") for u in owners),
                        "the loading lands on the transport supervisor desk")
        self.assertAlmostEqual(sum(cases.mapped("planned_tonnage")), 90.0, places=2)
        logs = self.env["itr.notification.dispatch.log"].sudo().search([
            ("event_key", "=", "slip.issued_to_transport"), ("res_id", "=", slip.id)])
        self.assertTrue(logs, "5.9: slip.issued_to_transport dispatched")

    def test_11_rerun_is_idempotent(self):
        case, slip, cases = self._handed_over(50.0, dispatches=2)
        before = len(cases)
        again = slip.with_user(self.fin_user).receive_by_transport()
        self.assertEqual(len(again), 0, "5.5: re-running creates nothing")
        self.assertEqual(len(slip.transport_case_ids), before)
        slip.with_user(self.fin_user).action_hand_over_to_transport()  # button double click
        self.assertEqual(len(slip.transport_case_ids), before)
        more = slip.with_user(self.fin_user).receive_by_transport(dispatch_count=3)
        self.assertEqual(len(more), 1, "only the missing dispatch number is added")

    def test_12_invoice_number_comes_from_own_slip(self):
        """5.7 / BR-055: two slips of one case -> two different sales_ref."""
        case = self._signed_case(100.0)
        slip1 = self._issued_slip(case, 40.0)
        slip2 = self._issued_slip(case, 60.0)
        slip1.with_user(self.fin_user).action_hand_over_to_transport()
        slip2.with_user(self.fin_user).action_hand_over_to_transport()
        tc1 = slip1.transport_case_ids[:1]
        tc2 = slip2.transport_case_ids[:1]
        self.assertEqual(tc1.sales_ref, slip1.name)
        self.assertEqual(tc2.sales_ref, slip2.name)
        self.assertNotEqual(tc1.sales_ref, tc2.sales_ref)
        # changing the case header never changes the snapshot of the loading
        case.with_user(self.fin_user).write({"proforma_sales_ref": "PF-CHANGED"})
        self.assertEqual(tc1.sales_ref, slip1.name)
        self.assertEqual(tc1.trade_case_id, case)
        self.assertEqual(tc2.trade_case_id, case, "N:1 - both loadings point to the same case")
        self.assertEqual(tc1.customer_id, self.buyer)
        self.assertEqual(tc1.factory_id, self.factory)
        self.assertEqual(tc1.goods_description, "TEST coil TRN")

    # ------------------------------------------------------------ negative
    def test_20_transport_user_cannot_create_slip(self):
        case = self._signed_case(10.0)
        # Odoo 19 assertRaises() does not accept a tuple of exception classes.
        try:
            self.Slip.with_user(self.transport_docs).create({
                "case_id": case.id, "customer_id": self.buyer.id,
                "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": 1.0})],
            })
            self.fail("transport docs user must not create a sales slip")
        except (AccessError, UserError):
            pass

    def test_21_manual_creation_outside_slip_path_refused(self):
        case, slip, cases = self._handed_over(10.0)
        # Odoo 19 assertRaises() does not accept a tuple of exception classes.
        try:
            self.Transport.with_user(self.transport_docs).create({
                "trade_case_id": case.id, "sales_slip_id": slip.id, "dispatch_no": 9})
            self.fail("transport docs user must not create a transport case outside the slip path")
        except (AccessError, UserError):
            pass
        with self.assertRaises(UserError):
            self.Transport.with_user(self.fin_user).create({
                "trade_case_id": case.id, "sales_slip_id": slip.id, "dispatch_no": 9})

    @mute_logger("odoo.sql_db")
    def test_22_database_refuses_duplicate_dispatch(self):
        case, slip, cases = self._handed_over(10.0)
        with self.assertRaises(Exception):
            with self.env.cr.savepoint():
                self.Transport.with_user(self.transport_sup).create({
                    "trade_case_id": case.id, "sales_slip_id": slip.id, "dispatch_no": 1})

    def test_23_direct_state_write_and_cancel_guards(self):
        case, slip, cases = self._handed_over(10.0)
        tc = cases[:1]
        with self.assertRaises(UserError):
            tc.with_user(self.transport_sup).write({"state": "closed"})
        with self.assertRaises(UserError):
            tc.sudo().write({"state": "closed"})
        with self.assertRaises(UserError):
            tc.with_user(self.transport_sup).action_cancel(reason="")
        with self.assertRaises(UserError):
            slip.with_user(self.fin_sup).action_cancel(reason="TEST slip with active loading")
        tc.with_user(self.transport_sup).action_cancel(reason="TEST cancel")
        self.assertEqual(tc.state, "cancelled")
        self.assertFalse(tc.current_owner_id)

    def test_24_administrator_never_owns_a_loading(self):
        case, slip, cases = self._handed_over(10.0)
        admin = self.env.ref("base.user_admin")
        self.assertNotIn(admin, cases.mapped("current_owner_id"))
        with self.assertRaises(UserError):
            cases[:1].with_user(self.ceo).assign_to(admin, reason="TEST admin")
PYEOF

write_utf8 "${TRN_DIR}/README.md" <<'MDEOF'
# itr_transport — transport / loading cases (phase 5 skeleton, phase 6 operations)

Depends on `itr_core`. Locked install order (Q02):
`itr_base -> itr_notify -> itr_core -> itr_transport -> itr_reports -> itr_integration`

## Contract with the finance side (phase 5)
* The finance unit issues `itr.sales.slip` and calls
  `slip.receive_by_transport(n)` (button *Hand over to transport*).
* This module implements `_create_transport_cases()`: one `itr.transport.case`
  per truck, idempotent (`unique(sales_slip_id, dispatch_no)` + row lock).
* Every loading carries a frozen snapshot with source references (BR-052) and
  the invoice number of ITS OWN slip (BR-055).

## Locked state names (G10)
`draft | pending_review | loading_authorized | loaded | in_transit |
waiting_weighbridge | waiting_bijak | waiting_clearance | waiting_payment |
delivered | settled | closed | cancelled` — phase 6 extends the transition
table through `_transition_table()` by inheritance; it never renames.

## Cartable
`current_owner_id`, `owner_deadline`, `assign_to()`, `_hand_over_to_group()`
come from `itr.cartable.mixin` (phase 5, same contract as the phase-4 trade
case). Phase 8 builds the unified work queue on these fields only.
MDEOF

log "ماژول itr_transport (اسکلت فاز ۵) نوشته شد"

# =============================================================================
step "5) پچ افزایشی و idempotent فایل‌های مشترک itr_core (C2) + FIX-P4-1"
# =============================================================================
python3 - "${CORE_DIR}" "${OPS_DIR}" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Incremental, idempotent patch of the shared phase-3/4 files (concern C2).

Never rewrites a phase-3/4 file: it only INSERTS what is missing. Running it
twice changes nothing (NFR-002). Any unexpected file shape aborts loudly.
"""
import io
import os
import sys

mod_dir, ops_dir = sys.argv[1], sys.argv[2]
changed = []


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


# ---- models/__init__.py (append in dependency order) ------------------------
path = os.path.join(mod_dir, "models", "__init__.py")
text = read(path)
for imp in (
    "from . import itr_cartable_mixin",
    "from . import itr_work_assignment_log",
    "from . import itr_validation_service_ext",
    "from . import itr_sales_slip",
    "from . import itr_trade_case_phase5",
):
    if imp not in text.splitlines():
        text = text.rstrip("\n") + "\n" + imp + "\n"
        changed.append("models/__init__.py + %s" % imp)
write(path, text)

# ---- tests/__init__.py ------------------------------------------------------
path = os.path.join(mod_dir, "tests", "__init__.py")
text = read(path)
imp = "from . import test_sales_slip_phase5"
if imp not in text:
    text = text.rstrip("\n") + "\n" + imp + "\n"
    changed.append("tests/__init__.py + %s" % imp)
write(path, text)

# ---- __manifest__.py --------------------------------------------------------
path = os.path.join(mod_dir, "__manifest__.py")
text = read(path)
anchor = '"views/itr_core_phase4_menus.xml",'
if anchor not in text:
    print("FATAL: manifest anchor not found - phase 4 contract changed", file=sys.stderr)
    sys.exit(2)
indent = "        "
entries = [
    '"security/itr_core_phase5_rules.xml",',
    '"data/itr_sales_slip_data.xml",',
    '"data/itr_core_phase5_notify_events.xml",',
    '"views/itr_sales_slip_views.xml",',
    '"views/itr_work_assignment_views.xml",',
    '"views/itr_core_phase5_menus.xml",',
]
last = anchor
for entry in entries:
    if entry not in text:
        text = text.replace(indent + last, indent + last + "\n" + indent + entry)
        changed.append("manifest + %s" % entry)
    last = entry
if '"version": "19.0.1.1.0",' in text:
    text = text.replace('"version": "19.0.1.1.0",', '"version": "19.0.1.2.0",')
    changed.append("manifest version -> 19.0.1.2.0")
write(path, text)
for entry in entries:
    if entry not in text:
        print("FATAL: manifest patch failed for %s" % entry, file=sys.stderr)
        sys.exit(2)

# ---- security/ir.model.access.csv -------------------------------------------
path = os.path.join(mod_dir, "security", "ir.model.access.csv")
text = read(path)
acl_lines = [
    "access_itr_sales_slip_user,itr.sales.slip user read,model_itr_sales_slip,base.group_user,1,0,0,0",
    "access_itr_sales_slip_fin_user,itr.sales.slip fin user,model_itr_sales_slip,itr_core.group_finance_user,1,1,1,1",
    "access_itr_sales_slip_fin_sup,itr.sales.slip fin sup,model_itr_sales_slip,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_sales_slip_fin_mgr,itr.sales.slip fin mgr,model_itr_sales_slip,itr_core.group_financial_manager,1,1,1,0",
    "access_itr_sales_slip_ceo,itr.sales.slip ceo,model_itr_sales_slip,itr_core.group_ceo,1,1,1,0",
    "access_itr_sales_slip_auditor,itr.sales.slip auditor,model_itr_sales_slip,itr_core.group_auditor,1,0,0,0",
    "access_itr_sales_slip_line_user,itr.sales.slip.line user read,model_itr_sales_slip_line,base.group_user,1,0,0,0",
    "access_itr_sales_slip_line_fin_user,itr.sales.slip.line fin user,model_itr_sales_slip_line,itr_core.group_finance_user,1,1,1,1",
    "access_itr_sales_slip_line_fin_sup,itr.sales.slip.line fin sup,model_itr_sales_slip_line,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_sales_slip_line_fin_mgr,itr.sales.slip.line fin mgr,model_itr_sales_slip_line,itr_core.group_financial_manager,1,1,1,0",
    "access_itr_sales_slip_line_ceo,itr.sales.slip.line ceo,model_itr_sales_slip_line,itr_core.group_ceo,1,1,1,0",
    "access_itr_work_assignment_log_user,itr.work.assignment.log user,model_itr_work_assignment_log,base.group_user,1,0,1,0",
]
for line in acl_lines:
    acl_id = line.split(",", 1)[0]
    if acl_id + "," not in text:
        text = text.rstrip("\n") + "\n" + line + "\n"
        changed.append("acl + %s" % acl_id)
write(path, text)

# ---- i18n/fa_IR.po (append-only block with a guard marker) -------------------
path = os.path.join(mod_dir, "i18n", "fa_IR.po")
text = read(path)
MARK = "#### itr_core phase-5 translations ####"
if MARK not in text:
    text = text.rstrip("\n") + "\n\n" + MARK + """

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_sales_slip
msgid "Trade Sales Slip"
msgstr "ریزفاکتور فروش"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_sales_slip_line
msgid "Trade Sales Slip Line"
msgstr "ردیف ریزفاکتور فروش"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_work_assignment_log
msgid "Work Item Assignment Log"
msgstr "تاریخچهٔ ارجاع کارها"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_cartable_mixin
msgid "ITR Cartable Mixin"
msgstr "قرارداد مشترک کارتابل"

#. module: itr_core
#: model:ir.actions.act_window,name:itr_core.action_itr_sales_slip
#: model:ir.ui.menu,name:itr_core.menu_itr_sales_slip
msgid "Sales Slips"
msgstr "ریزفاکتورهای فروش"

#. module: itr_core
#: model:ir.actions.act_window,name:itr_core.action_itr_work_assignment_log
#: model:ir.ui.menu,name:itr_core.menu_itr_work_assignment_log
msgid "Work Assignment Log"
msgstr "تاریخچهٔ ارجاع کارها"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_validation_bypass_log__check_kind__workflow_override
msgid "Workflow guard override"
msgstr "عبور از گارد گردش‌کار"

#. module: itr_core
#: code:addons/itr_core/models/itr_sales_slip.py:0
#, python-format
msgid "Only the finance unit (finance specialist, finance supervisor or CEO) may create or issue a sales slip (checklist 5.1)."
msgstr "فقط واحد مالی (کارشناس مالی، سرپرست مالی یا مدیرعامل) مجاز به ساخت یا صدور ریزفاکتور فروش است (بند 5.1)."

#. module: itr_core
#: code:addons/itr_core/models/itr_sales_slip.py:0
#, python-format
msgid "A sales slip can only be issued after the signed, scanned purchase document is uploaded on the trade case (G03 / BR-004). Case %(c)s is in state %(s)s."
msgstr "ریزفاکتور فروش فقط پس از بارگذاری اسکن سند امضاشدهٔ خرید روی پروندهٔ بازرگانی صادر می‌شود (G03 / BR-004). پروندهٔ %(c)s در وضعیت %(s)s است."

#. module: itr_core
#: code:addons/itr_core/models/itr_sales_slip.py:0
#, python-format
msgid "Total allocated tonnage %(alloc)s of goods row '%(item)s' exceeds its contract tonnage %(contract)s (checklist 5.3)."
msgstr "جمع تناژ تخصیص‌یافتهٔ %(alloc)s برای ردیف کالای «%(item)s» از تناژ قراردادی %(contract)s بیشتر است (بند 5.3)."

#. module: itr_core
#: code:addons/itr_core/models/itr_sales_slip.py:0
#, python-format
msgid "The transport module (itr_transport) is not installed, so no transport case can be created from sales slip %(n)s."
msgstr "ماژول حمل (itr_transport) نصب نیست؛ بنابراین هیچ پروندهٔ حملی از ریزفاکتور %(n)s ساخته نمی‌شود."

#. module: itr_core
#: code:addons/itr_core/models/itr_sales_slip.py:0
#, python-format
msgid "Lines of an issued slip are frozen (FIN-014)."
msgstr "ردیف‌های ریزفاکتور صادرشده قفل هستند (FIN-014)."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case_phase5.py:0
#, python-format
msgid "Goods row '%(n)s' is frozen: tonnage, rates, currency and row kind cannot change once the case entered the review chain (FIN-014). Return the case for completion first."
msgstr "ردیف کالای «%(n)s» قفل است: پس از ورود پرونده به زنجیرهٔ تأیید، تناژ/نرخ/ارز/نوع ردیف تغییر نمی‌کند (FIN-014). ابتدا پرونده را برای تکمیل بازگردانید."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case_phase5.py:0
#, python-format
msgid "Reserved / effective tonnage are written only by the tonnage engine (phase 5 / phase 6), never by hand (OPS-023)."
msgstr "تناژ رزروشده/مؤثر فقط توسط موتور تناژ (فاز ۵/۶) نوشته می‌شود، هرگز دستی (OPS-023)."

#. module: itr_core
#: code:addons/itr_core/models/itr_cartable_mixin.py:0
#, python-format
msgid "Administrator, OdooBot or an archived user can never own a work item (SEC-002)."
msgstr "مدیر سیستم، OdooBot یا کاربر غیرفعال هرگز نمی‌تواند مالک یک کار باشد (SEC-002)."
"""
    changed.append("i18n/fa_IR.po + phase-5 block")
write(path, text)

# ---- [FIX-P4-1] phase-scoped assertion of phase 4 (documented exception) -----
# The phase-4 test asserted the ABSENCE of the itr.sales.slip model. That claim
# is true only inside phase 4 and breaks by design once phase 5 is delivered.
# It is replaced by the real BR-004 requirement: no slip exists for a case that
# waits for supply. Anchored, idempotent, backed up (docs/phase5-backup).
path = os.path.join(mod_dir, "tests", "test_trade_case_phase4.py")
text = read(path)
old_test = (
    '        self.assertNotIn("itr.sales.slip", self.env,\n'
    '                         "4.4/BR-004: itr.sales.slip must not exist in phase 4")\n'
)
new_test = (
    '        # [FIX-P4-1] phase-5 aware BR-004: no sales slip - not even a draft -\n'
    '        # exists while the case waits for supply (phase 4 asserted the absence\n'
    '        # of the model itself, which is true only inside phase 4).\n'
    '        if "itr.sales.slip" in self.env:\n'
    '            self.assertEqual(\n'
    '                self.env["itr.sales.slip"].sudo().search_count([("case_id", "=", case.id)]), 0,\n'
    '                "4.4/BR-004: no sales slip may exist while waiting for supply")\n'
)
if old_test in text:
    text = text.replace(old_test, new_test)
    changed.append("tests/test_trade_case_phase4.py [FIX-P4-1] BR-004 assertion made phase-5 aware")
    write(path, text)
elif new_test not in text:
    print("FATAL: phase-4 BR-004 assertion anchor not found (neither old nor new form)", file=sys.stderr)
    sys.exit(2)

path = os.path.join(ops_dir, "verify", "verify_phase4.py")
if os.path.exists(path):
    text = read(path)
    old_v = '    no_slip = "itr.sales.slip" not in env\n'
    new_v = (
        '    # [FIX-P4-1] phase-5 aware BR-004 (no slip for a case waiting for supply)\n'
        '    no_slip = ("itr.sales.slip" not in env) or env["itr.sales.slip"].sudo().search_count(\n'
        '        [("case_id", "=", case_b.id)]) == 0\n'
    )
    if old_v in text:
        text = text.replace(old_v, new_v)
        changed.append("ops/verify/verify_phase4.py [FIX-P4-1]")
        write(path, text)
    elif new_v not in text:
        print("FATAL: verify_phase4 BR-004 anchor not found", file=sys.stderr)
        sys.exit(2)

print("PATCH_RESULT changed=%d" % len(changed))
for item in changed:
    print(" - " + item)
PYEOF
PATCH_RC=$?
[[ ${PATCH_RC} -eq 0 ]] || err "پچ افزایشی فایل‌های مشترک شکست خورد — هیچ نصبی انجام نمی‌شود (rollback: ${P5_BACKUP_DIR}/${TS})"
cp -f "${CORE_DIR}/i18n/fa_IR.po" "${CORE_DIR}/i18n/fa.po"
gate "G5-04" "پچ افزایشی idempotent فایل‌های مشترک بدون بازنویسی فاز ۳/۴ (C2) + FIX-P4-1 لنگرشده" "PASS" "backup=${P5_BACKUP_DIR}/${TS}"

# =============================================================================
step "6) verify مستقل فاز ۵ (ops/verify/verify_phase5.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase5.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Independent verify of Phase 5 (V5-01 .. V5-10) - odoo shell, real users,
rolled back at the end (ADR-005 / Q15 / G01)."""
import base64
import sys
import traceback

from odoo.exceptions import AccessError, UserError, ValidationError

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
    print("ITR_VERIFY %-6s [%s] %s %s" % (code, st, title, ("- " + str(detail)) if detail else ""))


try:
    Users = env["res.users"]

    def real(login):
        user = Users.search([("login", "=", login)], limit=1)
        assert user, "seeded user missing: %s" % login
        return user

    ceo = real("hadi.karamian@irbco.local")
    fin_user = real("faezeh.heydari@irbco.local")
    fin_sup = real("ehsan.nahalparvar@irbco.local")
    legal = real("pouya.soleimani@irbco.local")
    treasury = real("atieh.alaei@irbco.local")
    receivables = real("zahra.mirzaei@irbco.local")
    transport_docs = real("mohaddeseh.enayati@irbco.local")

    Case = env["itr.trade.case"].with_context(itr_notify_sync=True)
    Slip = env["itr.sales.slip"].with_context(itr_notify_sync=True)
    buyer = env["res.partner"].sudo().create({"name": "TEST verify buyer", "is_company": True})

    def signed_case(tonnage=100.0):
        case = Case.with_user(fin_user).create({
            "requested_by": ceo.id, "deal_pattern": "buy_first",
            "item_ids": [(0, 0, {"name": "TEST verify coil", "row_kind": "both",
                                 "contract_tonnage": tonnage, "purchase_price_unit": 100.0,
                                 "sale_price_unit": 120.0})],
        })
        case.with_user(fin_user).action_submit()
        case.with_user(legal).action_legal_approve()
        case.with_user(treasury).action_treasury_approve()
        case.with_user(receivables).action_receivables_approve()
        case.with_context(itr_trade_state_engine=True).write({
            "signed_document": base64.b64encode(b"TEST"), "signed_document_filename": "s.pdf"})
        case.with_user(fin_sup).action_confirm_signed()
        return case

    def new_slip(case, tonnage, user=fin_user, dispatches=1):
        return Slip.with_user(user).create({
            "case_id": case.id, "customer_id": buyer.id, "dispatch_count": dispatches,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": tonnage})],
        })

    case = signed_case(100.0)
    slip = new_slip(case, 30.0)
    chk("V5-01", "ریزفاکتور با Sequence خودکار روی پروندهٔ امضاشده ساخته شد (5.1)",
        bool(slip.id) and slip.name.startswith("SS/"), slip.name)

    refused = False
    try:
        with env.cr.savepoint():
            new_slip(case, 5.0, user=transport_docs)
    except (AccessError, UserError):
        refused = True
    chk("V5-02", "کاربر گروه حمل نمی‌تواند ریزفاکتور بسازد — حتی از API (5.1)", refused)

    case_ns = Case.with_user(fin_user).create({
        "requested_by": ceo.id, "deal_pattern": "buy_first",
        "item_ids": [(0, 0, {"name": "TEST unsigned", "row_kind": "both", "contract_tonnage": 10.0,
                             "purchase_price_unit": 1.0, "sale_price_unit": 2.0})]})
    case_ns.with_user(fin_user).action_submit()
    case_ns.with_user(legal).action_legal_approve()
    case_ns.with_user(treasury).action_treasury_approve()
    case_ns.with_user(receivables).action_receivables_approve()
    blocked = blocked_su = False
    try:
        with env.cr.savepoint():
            new_slip(case_ns, 1.0)
    except UserError:
        blocked = True
    try:
        with env.cr.savepoint():
            Slip.sudo().create({"case_id": case_ns.id, "customer_id": buyer.id,
                                "line_ids": [(0, 0, {"case_item_id": case_ns.item_ids[0].id, "allocated_tonnage": 1.0})]})
    except UserError:
        blocked_su = True
    chk("V5-03", "ریزفاکتور پیش از سند امضاشده مسدود است، حتی برای مدیر سیستم (5.2/G03)", blocked and blocked_su)

    over = False
    try:
        with env.cr.savepoint():
            new_slip(case, 80.0)
    except ValidationError:
        over = True
    chk("V5-04", "تناژ مازاد بر سقف ردیف کالا رد شد (5.3)", over)

    slip2 = new_slip(case, 30.0)
    slip3 = new_slip(case, 40.0)
    slip.with_user(fin_user).action_issue()
    slip2.with_user(fin_sup).action_issue()
    slip3.with_user(ceo).action_issue()
    item = case.item_ids[0]
    chk("V5-05", "سه ریزفاکتور برای یک ردیف خرید صادر شد؛ پرونده slips_issued؛ رزرو=۱۰۰ (تست مثبت ۱)",
        case.state == "slips_issued" and abs(item.reserved_tonnage - 100.0) < 1e-6,
        "state=%s reserved=%s" % (case.state, item.reserved_tonnage))

    has_transport = "itr.transport.case" in env
    if has_transport:
        slip.with_context(itr_notify_sync=True).with_user(fin_user).write({"dispatch_count": 2})
        slip.with_user(fin_user).action_hand_over_to_transport()
        cases = slip.transport_case_ids
        owners = cases.mapped("current_owner_id")
        chk("V5-06", "با تحویل به حمل، پرونده‌های حمل در کارتابل سرپرست حمل ظاهر شدند (5.9 / تست مثبت ۲)",
            len(cases) == 2 and all(u.has_group("itr_core.group_transport_supervisor") for u in owners)
            and all(c.state == "pending_review" for c in cases),
            "cases=%d owners=%s" % (len(cases), owners.mapped("name")))
        again = slip.with_user(fin_user).receive_by_transport()
        chk("V5-07", "اجرای دوبارهٔ ایجاد پروندهٔ حمل رکورد دوم نساخت (5.5 Idempotency)",
            len(again) == 0 and len(slip.transport_case_ids) == 2)
        slip2.with_user(fin_user).action_hand_over_to_transport()
        tc1 = slip.transport_case_ids.sorted("dispatch_no")[:1]
        tc2 = slip2.transport_case_ids[:1]
        chk("V5-08", "رابطهٔ N:1 با دادهٔ آزمایشی اثبات شد (دو ریزفاکتور → چند حمل → یک پرونده)",
            tc1.trade_case_id == case and tc2.trade_case_id == case
            and len(case.sales_slip_ids.mapped("transport_case_ids")) >= 3)
        case.with_user(fin_user).write({"proforma_sales_ref": "PF-X"})
        chk("V5-09", "شمارهٔ فاکتور هر بارگیری از ریزفاکتور خودش می‌آید نه سربرگ (5.7/BR-055)",
            tc1.sales_ref == slip.name and tc2.sales_ref == slip2.name and tc1.sales_ref != tc2.sales_ref)
    else:
        chk("V5-06", "itr_transport نصب نیست", False, "install itr_transport")
        chk("V5-07", "itr_transport نصب نیست", False)
        chk("V5-08", "itr_transport نصب نیست", False)
        chk("V5-09", "itr_transport نصب نیست", False)

    service = env["itr.validation.service"].with_user(transport_docs)
    fixed = False
    try:
        with env.cr.savepoint():
            service.check_plate("TR 34 ABC 12", plate_type="iranian")
    except ValidationError:
        fixed = True
    chk("V5-10", "[FIX-P3-1] لایهٔ Guarded مقدار 'iranian' را ایرانی می‌شناسد و پلاک نامعتبر را رد می‌کند", fixed)

except Exception as error:  # noqa: BLE001
    traceback.print_exc()
    failed += 1
    checks.append(("V5-ERR", "FAIL", "verify crashed", str(error)))

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
log "ops/verify/verify_phase5.py نوشته شد"

# =============================================================================
step "7) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python3 - "$CORE_DIR" "$TRN_DIR" "$OPS_DIR" <<'PYEOF'
import ast, csv, io, os, sys
import xml.etree.ElementTree as ET

core_dir, trn_dir, ops_dir = sys.argv[1], sys.argv[2], sys.argv[3]
errors = []
py_count = xml_count = 0
for root_dir in (core_dir, trn_dir, os.path.join(ops_dir, "verify")):
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
rows_total = 0
for mod in (core_dir, trn_dir):
    acl = os.path.join(mod, "security", "ir.model.access.csv")
    with io.open(acl, encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    seen = set()
    for row in rows:
        rid = (row.get("id") or "").strip()
        if not rid:
            continue
        if rid in seen:
            errors.append("CSV duplicate acl id: %s" % rid)
        seen.add(rid)
        if not row.get("model_id:id") or not row.get("group_id:id"):
            errors.append("CSV incomplete row: %s" % row)
    rows_total += len(rows)
print("checked: %d python file(s), %d xml file(s), %d acl row(s)" % (py_count, xml_count, rows_total))
if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
SYNTAX_RC=$?
set -e
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G5-05" "نحو پایتون/XML/CSV هر دو ماژول سالم است" "PASS" "pre-install static check"
else
  gate "G5-05" "نحو پایتون/XML/CSV هر دو ماژول سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب (rollback: ${P5_BACKUP_DIR}/${TS})"
fi

# =============================================================================
step "8) ارتقای itr_core + نصب itr_transport روی ${DB_NAME} (Q01/NFR-001)"
# =============================================================================
TRN_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${CORE_MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
RC1=$?
if [[ ${RC1} -eq 0 ]]; then
  TRN_FLAG="-i"; [[ "${TRN_STATE}" == "installed" ]] && TRN_FLAG="-u"
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    "${TRN_FLAG}" "${TRN_MODULE}" --stop-after-init --log-level=info >>"${INSTALL_LOG}" 2>&1
  RC2=$?
else
  RC2=1
fi
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
CORE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TRN_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
echo "rc_core=${RC1} rc_transport=${RC2} errors=${INSTALL_ERRORS} core=${CORE_AFTER} transport=${TRN_AFTER}"
if [[ ${RC1} -eq 0 && ${RC2} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${CORE_AFTER}" == "installed" && "${TRN_AFTER}" == "installed" ]]; then
  gate "G5-06" "ارتقای itr_core (بخش سوم) + نصب itr_transport بدون خطا" "PASS" "core=installed transport=installed"
else
  gate "G5-06" "ارتقای itr_core (بخش سوم) + نصب itr_transport بدون خطا" "FAIL" "rc=${RC1}/${RC2} errors=${INSTALL_ERRORS} → ${INSTALL_LOG}"
  tail -n 60 "${INSTALL_LOG}"
fi

TBL_SLIP="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_sales_slip')")"
TBL_LINE="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_sales_slip_line')")"
TBL_TRN="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_transport_case')")"
TBL_WLOG="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_work_assignment_log')")"
SEQ_SLIP="$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code='itr.sales.slip'")"
SEQ_TRN="$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code='itr.transport.case'")"
IDEMP_IDX="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE tablename='itr_transport_case' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%sales_slip_id%' AND indexdef ILIKE '%dispatch_no%'")"
EV_SLIP="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key='slip.issued_to_transport'")"
EV_TRN="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key='transport.case_created'")"
UNIQ_SLIP_FK="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE tablename='itr_transport_case' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%btree (sales_slip_id)%'")"
echo "slip=${TBL_SLIP} line=${TBL_LINE} transport=${TBL_TRN} wlog=${TBL_WLOG} seq=${SEQ_SLIP}/${SEQ_TRN} idemp_idx=${IDEMP_IDX} events=${EV_SLIP}/${EV_TRN} slip_fk_unique=${UNIQ_SLIP_FK:-0}"
if [[ "${TBL_SLIP}" == "itr_sales_slip" && "${TBL_LINE}" == "itr_sales_slip_line" && "${TBL_TRN}" == "itr_transport_case" \
      && "${TBL_WLOG}" == "itr_work_assignment_log" && "${SEQ_SLIP}" == "1" && "${SEQ_TRN}" == "1" \
      && "${IDEMP_IDX}" -ge 1 && "${EV_SLIP}" == "1" && "${EV_TRN}" == "1" && "${UNIQ_SLIP_FK:-0}" == "0" ]]; then
  gate "G5-07" "مدل‌ها/Sequence/رویدادها + کلید Idempotency واقعی (slip,dispatch) + رابطهٔ N:1 غیر یکتا" "PASS" \
       "4 tables, 2 seq, 2 events, unique(sales_slip_id,dispatch_no)=1, unique(sales_slip_id)=0"
else
  gate "G5-07" "مدل‌ها/Sequence/رویدادها + کلید Idempotency واقعی + رابطهٔ N:1 غیر یکتا" "FAIL" \
       "slip=${TBL_SLIP} trn=${TBL_TRN} wlog=${TBL_WLOG} seq=${SEQ_SLIP}/${SEQ_TRN} idx=${IDEMP_IDX} ev=${EV_SLIP}/${EV_TRN} fkuniq=${UNIQ_SLIP_FK}"
fi

# =============================================================================
step "9) تست‌های خودکار — فاز ۵ *و* بازاجرای فازهای ۳/۴ (Q04 + اثبات C2)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G5-08" "تست‌های خودکار فاز ۵ + بازاجرای ۳/۴ سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "${CORE_MODULE},${TRN_MODULE}" --test-enable --test-tags "/${CORE_MODULE},/${TRN_MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" && -n "${TEST_TOTAL}" ]]; then
    gate "G5-08" "تست‌های فاز ۵ سبز + تست‌های فازهای ۳/۴ دوباره سبز (چیزی نشکست — C2)" "PASS" "${TEST_TOTAL} rc=0"
  else
    gate "G5-08" "تست‌های خودکار فاز ۵ + بازاجرای ۳/۴ سبز هستند" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-none} → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_|At least one test failed|Traceback \(most recent' "${TEST_LOG}" | head -n 20 || true
  fi
fi

# =============================================================================
step "10) verify مستقل V5-01..V5-10 (بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G5-09" "verify مستقل فاز ۵ سبز است (V5-01..V5-10)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase5.py" >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G5-09" "verify مستقل فاز ۵ سبز است (V5-01..V5-10)" "PASS" "${VERIFY_LINE}"
  else
    gate "G5-09" "verify مستقل فاز ۵ سبز است (V5-01..V5-10)" "FAIL" "${VERIFY_LINE:-خروجی یافت نشد} (rc=${VERIFY_RC}) → ${VERIFY_LOG}"
    tail -n 40 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "11) گاردهای معماری فاز ۵ (CRM ممنوع + G18 + Q05 + G01 + Q03)"
# =============================================================================
CRM_DEP="$(grep -rnE '"crm"' --include='__manifest__.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
CRM_INSTALLED="$(q "${DB_NAME}" "SELECT count(*) FROM ir_module_module WHERE name='crm' AND state='installed'")"
CRM_DOC="$(grep -c 'BR-051' "${CORE_DIR}/models/itr_sales_slip.py" || true)"
if [[ -z "${CRM_DEP}" && "${CRM_INSTALLED:-0}" == "0" && "${CRM_DOC}" -ge 1 ]]; then
  gate "G5-10" "هیچ ماژول CRM نصب/وابسته نشد؛ معنای رسمی «CRM» در کد مستند است (BR-051/X16)" "PASS" "grep clean, crm not installed"
else
  gate "G5-10" "هیچ ماژول CRM نصب/وابسته نشد (BR-051/X16)" "FAIL" "dep=${CRM_DEP:-none} installed=${CRM_INSTALLED} doc=${CRM_DOC}"
fi

PROFIT_HITS="$(grep -rnE 'estimated_profit|sales_base *-.*purchase_base' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -vE '/models/money_engine\.py' | grep -v '/itr_core/models/itr_trade_case.py' | grep -v '/tests/' | grep -v '/ops/verify/' || true)"
if [[ -z "${PROFIT_HITS}" ]]; then
  gate "G5-11" "فقط یک موتور محاسبهٔ سود (FIN-005/G18)" "PASS" "money_engine.py"
else
  gate "G5-11" "فقط یک موتور محاسبهٔ سود (FIN-005/G18)" "FAIL" "$(echo "${PROFIT_HITS}" | head -n3 | tr '\n' ' ')"
fi

TASK_HITS="$(grep -rnE '_name = "itr\.(task|work\.queue|todo|cartable\.item)' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
MIXIN_USES="$(grep -rlE '"itr\.cartable\.mixin"' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v itr_cartable_mixin.py | wc -l | tr -d ' ')"
if [[ -z "${TASK_HITS}" && "${MIXIN_USES}" -ge 2 ]]; then
  gate "G5-12" "هیچ موتور Task/صف دوم؛ یک قرارداد کارتابل (mixin) روی ریزفاکتور و پروندهٔ حمل (C1/G18/UX-011)" "PASS" "mixin used by ${MIXIN_USES} model(s)"
else
  gate "G5-12" "هیچ موتور Task/صف دوم؛ قرارداد واحد کارتابل (C1/G18)" "FAIL" "task=${TASK_HITS:-none} mixin_uses=${MIXIN_USES}"
fi

SUDO_HITS="$(grep -rn --include='*.py' '\.sudo(' "${CORE_DIR}/models" "${TRN_DIR}/models" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G5-13" "هیچ sudo() بدون مجوز صریح در منطق ماژول‌ها (G01/SEC-018)" "PASS" "models/ تمیز"
else
  gate "G5-13" "هیچ sudo() بدون مجوز صریح در منطق ماژول‌ها (G01/SEC-018)" "FAIL" "$(echo "${SUDO_HITS}" | head -n3 | tr '\n' ' ')"
fi

NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${CORE_DIR}" "${TRN_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${CORE_DIR}/security" "${CORE_DIR}/views" "${TRN_DIR}/security" "${TRN_DIR}/views" 2>/dev/null | grep -v 'fa_IR' || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G5-14" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n/data"
else
  gate "G5-14" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

ADMIN_GROUPS="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_core' WHERE u.login='admin'")"
ADMIN_OWNER="$(q "${DB_NAME}" "SELECT (SELECT count(*) FROM itr_sales_slip s JOIN res_users u ON u.id=s.current_owner_id WHERE u.login='admin') + (SELECT count(*) FROM itr_transport_case t JOIN res_users u ON u.id=t.current_owner_id WHERE u.login='admin')")"
if [[ "${ADMIN_GROUPS}" == "0" && "${ADMIN_OWNER:-0}" == "0" ]]; then
  gate "G5-15" "Administrator بدون نقش کسب‌وکاری و بدون هیچ ریزفاکتور/پروندهٔ حمل در کارتابل (Q03/UX-003)" "PASS" "0 group / 0 owned"
else
  gate "G5-15" "Administrator بدون نقش کسب‌وکاری و بدون کارتابل (Q03/UX-003)" "FAIL" "groups=${ADMIN_GROUPS} owned=${ADMIN_OWNER}"
fi

# =============================================================================
step "12) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code IN ('itr.sales.slip','itr.transport.case')")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module IN ('itr_core','itr_transport')")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${CORE_MODULE},${TRN_MODULE}" \
  --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code IN ('itr.sales.slip','itr.transport.case')")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module IN ('itr_core','itr_transport')")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G5-16" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "events|seq|xmlid = ${CNT_AFTER}"
else
  gate "G5-16" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "13) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G5-17" "فاز ۵ روی محیط UAT نصب شد" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G5-17" "فاز ۵ روی محیط UAT نصب شد" "WARN" "محیط UAT یافت نشد"
else
  UAT_TRN_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" -u "${CORE_MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC1=$?
  UAT_FLAG="-i"; [[ "${UAT_TRN_STATE}" == "installed" ]] && UAT_FLAG="-u"
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" "${UAT_FLAG}" "${TRN_MODULE}" --stop-after-init --log-level=warn >>"${UAT_LOG}" 2>&1
  UAT_RC2=$?
  set -e
  UAT_AFTER="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  if [[ ${UAT_RC1} -eq 0 && ${UAT_RC2} -eq 0 && "${UAT_AFTER}" == "installed" ]]; then
    gate "G5-17" "فاز ۵ روی محیط UAT نصب شد" "PASS" "${DB_NAME_UAT} transport=installed"
  else
    gate "G5-17" "فاز ۵ روی محیط UAT نصب شد" "FAIL" "rc=${UAT_RC1}/${UAT_RC2} state=${UAT_AFTER} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "14) اسناد حاکمیتی: ADR-023..027 / REUSE MAP / تحویل"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-023" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-023 — جای‌گذاری ریزفاکتور و پروندهٔ حمل و الگوی hook (فاز ۵ — Q02)
ریزفاکتور فروش سند مالی است و در itr_core (بخش سوم) زندگی می‌کند؛ پروندهٔ حمل
سند میدانی است و در ماژول itr_transport. جهت وابستگی همیشه یک‌طرفه است
(itr_transport → itr_core). قرارداد receive_by_transport() در core تعریف و
_create_transport_cases() در itr_transport با _inherit پیاده می‌شود. «CRM» در
این پروژه دقیقاً همین hook انتقال داده است، نه یک ماژول (BR-051/X16).

## ADR-024 — قفل رسمی نام‌های وضعیت پروندهٔ حمل (فاز ۵ — G10/Q11)
سیزده نام فنی state مدل itr.transport.case از این لحظه قفل هستند:
draft | pending_review | loading_authorized | loaded | in_transit |
waiting_weighbridge | waiting_bijak | waiting_clearance | waiting_payment |
delivered | settled | closed | cancelled
فاز ۶ فقط جدول انتقال را از طریق _transition_table() با _inherit گسترش می‌دهد؛
هیچ نامی اضافه/حذف/تغییر نمی‌کند. نوشتن مستقیم state حتی با sudo مسدود است.

## ADR-025 — قرارداد واحد کارتابل با mixin (فاز ۵ — C1/UX-011/G18)
itr.cartable.mixin همان قرارداد ADR-019 (current_owner_id، owner_deadline،
assign_to()، _hand_over_to_group() با «کم‌بارترین» G15، لاگ افزودنی) را برای
ریزفاکتور، پروندهٔ حمل و هر کار آیندهٔ فاز ۶ فراهم می‌کند. itr.trade.case فاز ۴
دست‌نخورده می‌ماند (همان امضاها). تاریخچه: itr.case.assignment.log (پرونده) +
itr.work.assignment.log (سایر کارها) — هر دو فقط تاریخ‌اند، نه موتور Task.
صف کار واحد فاز ۸ فقط روی این سه ستون ساخته می‌شود.

## ADR-026 — کلید Idempotency واقعی ایجاد پروندهٔ حمل (فاز ۵ — 5.5)
unique(sales_slip_id, dispatch_no) با models.Constraint (ADR-022) + قفل سطر
ریزفاکتور با SELECT … FOR UPDATE پیش از شمارش. اجرای دوبارهٔ همان عملیات
فقط شماره‌های اعزام غایب را می‌سازد. هیچ ایندکس یکتایی روی sales_slip_id به
تنهایی وجود ندارد (BR-002: رابطه هرگز ۱:۱ نیست) — با pg_indexes اثبات می‌شود.

## ADR-027 — اصلاح‌های افزایشی فازهای قبل بدون بازنویسی (فاز ۵ — C2/C4)
[FIX-P3-1] لایهٔ Guarded فقط 'ir' را ایرانی می‌شناخت؛ فاز ۳ 'iranian' می‌فرستاد ⇒
  سنجهٔ کدملی/پلاک ایرانی دور زده می‌شد. اصلاح با _inherit روی
  itr.validation.service (normalize_origin) + تست منفی.
[FIX-P4-1] تست/verify فاز ۴ «نبودِ مدل itr.sales.slip» را assert می‌کرد که فقط
  داخل فاز ۴ درست بود؛ با جایگزین معنایی BR-004 (نبود ریزفاکتور برای پروندهٔ
  در انتظار تأمین) به‌صورت لنگرشده و idempotent پچ شد (تنها استثنای آگاهانهٔ
  قاعدهٔ «بدون بازنویسی» — پشتیبان در docs/phase5-backup/).
[FIX-P4-2] ردیف کالا پس از ورود به تأییدات در سرور قفل می‌شود (FIN-014) و
  reserved/effective فقط با context موتور تناژ نوشته می‌شوند.
MDEOF
log "ADR-023..027 به ARCHITECTURE_DECISIONS.md افزوده شد"
else
  warn "ADR-023 از قبل ثبت شده — بدون تغییر"
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "itr.cartable.mixin" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## فاز ۵ — ریزفاکتور فروش + itr_transport (Q14)
| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۵ | `itr.trade.case.mark_slips_issued()` و جدول انتقال فاز ۴ | گذار approved→slips_issued فقط از همان موتور (ADR-017) |
| ۵ | `itr.money.engine.item_side_base` برای snapshot مبالغ | تنها موتور مالی (FIN-005) |
| ۵ | `itr.fx.service.apply_fx` برای قفل نرخ ردیف ریزفاکتور | تنها موتور ارز (G12/FIN-014) |
| ۵ | `itr.validation.service.log_bypass` برای عبور از گارد امضا | تنها دفتر عبور (VAL-006) |
| ۵ | `itr.notification.service.notify()` (۲ رویداد جدید) | تنها نقطهٔ ورود اعلان |
| ۵ | `itr.supervisor.team.get_subordinate_users` در mixin | تنها مدل تیم (SEC-004) |
| ۵ | `ir.sequence` برای SS/ و TR/ | شماره‌ساز دوم ممنوع |

## آنچه فاز ۶ باید از فاز ۵ بازاستفاده کند (ساخت دوباره = Gate قرمز)
* `itr.transport.case` + `_transition_table()` → فاز ۶ فقط با `_inherit` گسترش می‌دهد.
* `itr.cartable.mixin` → برای itr.payment.request و هر کار جدید.
* `source_item_id` + `planned_tonnage` → مبنای roll-up تناژ مؤثر (OPS-023) و کسری (BR-111).
* `itr.trade.case.item.effective_tonnage` فقط با context `itr_tonnage_engine` نوشته می‌شود.
MDEOF
log "docs/REUSE_MAP.md به‌روزرسانی شد"
fi

# =============================================================================
step "15) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G5-18" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
else
  if ! port_in_use "${HTTP_PORT}"; then
    rm -f "${PID_FILE}"
    nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
      --http-interface="${HTTP_INTERFACE}" --http-port="${HTTP_PORT}" >"${LOG_FILE}" 2>&1 &
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
    gate "G5-18" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G5-18" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "16) ثبت Git + تگ phase-5 (Q09) + اسکن رمز (Q12)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-5: sales slip (post-signature only, tonnage cap, issuer roles), cartable mixin, itr_transport skeleton with idempotent N:1 auto-creation and BR-052/BR-055 snapshot, FIX-P3-1/FIX-P4-1/FIX-P4-2"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-5 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-5 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G5-19" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-5}"
else
  gate "G5-19" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi

SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' | grep -v 'test_itr' | grep -v 'test_notify' | grep -v 'required_fields' | grep -v 'itr_core_users_data.xml' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G5-20" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "PASS" "clean"
else
  gate "G5-20" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 5 — گزارش پذیرش فاز ۵"
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

write_utf8 "${DOC_DIR}/PHASE5-DELIVERY.md" <<MDEOF
# تحویل فاز ۵ — ریزفاکتور فروش + ایجاد خودکار پروندهٔ حمل (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-5
- وضعیت Gate 5: **${GATE_STATUS}** (هشدار: ${WARNS})

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 5.1 | itr.sales.slip با گارد نقشی سرور (finance_user/finance_supervisor/CEO)؛ حمل حتی از API رد می‌شود | SEC-016، بخش ۳ |
| 5.2 | گارد سرور: بدون signed_document ساخته نمی‌شود (حتی sudo)؛ عبور فقط با override + دلیل + دفتر عبور | G03، BR-004، VAL-006/007 |
| 5.3 | Σ allocated_tonnage یک ردیف ≤ تناژ قراردادی (ValidationError فارسی از i18n) | BR-005 |
| 5.4 | receive_by_transport(): تنها راه اطلاع حمل؛ بدون هیچ فاکتور/سند حسابداری | FIN-016، BR-051 |
| 5.5 | ایجاد idempotent با unique(sales_slip_id, dispatch_no) واقعی + SELECT FOR UPDATE | NFR-002، ADR-026 |
| 5.6 | snapshot کامل با مرجع منبع (پرونده، ریزفاکتور، ردیف کالا) | BR-052 |
| 5.7 | sales_ref هر بارگیری = شمارهٔ ریزفاکتور خودش؛ تغییر سربرگ اثری ندارد (تست) | BR-055 |
| 5.8 | ۱ ریزفاکتور → N پروندهٔ حمل؛ هیچ ایندکس یکتایی روی sales_slip_id | BR-002 |
| 5.9 | اکشن «تحویل به واحد حمل» + رویداد slip.issued_to_transport + transport.case_created | NOT-001 |
| C1 | itr.cartable.mixin (قرارداد فاز ۴) + itr.work.assignment.log؛ حمل روی میز سرپرست حمل (کم‌بارترین) | UX-011، G15، ADR-025 |
| C2 | fingerprint ۲۲ قرارداد + پچ افزایشی + پشتیبان + بازاجرای تست‌های فاز ۳/۴ | پیوست ج، ADR-021 |
| C4 | FIX-P3-1 (نام مستعار ایرانی در Guarded)، FIX-P4-1 (تست فازمحور BR-004)، FIX-P4-2 (قفل سرور ردیف کالا) | ADR-027 |

## ۲) Scope خارج از فاز (عمداً انجام نشد)
تب‌های عملیاتی حمل، بارنامه/باسکول/بیجک/ترخیص/POD، هزینهٔ داینامیک، چرخهٔ پرداخت،
چک‌لیست بستن و دفتر طلب (فاز ۶ — با _inherit روی همین ماژول itr_transport)،
ماتریس نهایی Record Rule (فاز ۷)، کارتابل ده‌بخشی (فاز ۸)، گزارش‌ها (فاز ۹).

## ۳) فایل‌های ایجادشده (جدید) و پچ‌شده (افزایشی)
\`\`\`
[NEW] itr_core/models/{itr_cartable_mixin.py, itr_work_assignment_log.py,
                      itr_validation_service_ext.py, itr_sales_slip.py, itr_trade_case_phase5.py}
[NEW] itr_core/security/itr_core_phase5_rules.xml
[NEW] itr_core/data/{itr_sales_slip_data.xml, itr_core_phase5_notify_events.xml}
[NEW] itr_core/views/{itr_sales_slip_views.xml, itr_work_assignment_views.xml, itr_core_phase5_menus.xml}
[NEW] itr_core/tests/test_sales_slip_phase5.py
[NEW] itr_transport/ (ماژول کامل اسکلت: manifest, models, security, data, views, i18n, tests, README)
[NEW] ops/verify/verify_phase5.py
[PATCH] itr_core/__manifest__.py, models/__init__.py, tests/__init__.py, security/ir.model.access.csv, i18n/fa_IR.po+fa.po
[PATCH-FIX-P4-1] itr_core/tests/test_trade_case_phase4.py (۲ خط لنگرشده), ops/verify/verify_phase4.py (۱ خط)
پشتیبان فایل‌های مشترک: docs/phase5-backup/${TS}/
\`\`\`

## ۴) ماتریس دسترسی تغییرکرده (خلاصه)
| مدل | user | fin_user | fin_sup | fin_mgr | ceo | trn_sup | docs/customs/delivery | auditor |
|---|---|---|---|---|---|---|---|---|
| itr.sales.slip | r | rwcu | rwcu | rwc | rwc | r | r | r |
| itr.sales.slip.line | r | rwcu | rwcu | rwc | rwc | r | r | - |
| itr.transport.case | r | rwc (فقط مسیر ریزفاکتور) | rwc | r | rwc | rwc | rw | r |
| itr.work.assignment.log | r+c (append-only در مدل) | ... | ... | ... | ... | ... | ... | r |

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
bash ops/restore.sh <آخرین dump پیش از فاز> <آخرین filestore.tar.gz> ${DB_NAME}
git -C ${CUSTOM_ADDONS} checkout phase-4 -- ${CORE_MODULE} ops/verify/verify_phase4.py
rm -rf ${TRN_DIR}     # ماژول جدید فاز ۵
# یا فقط فایل‌های مشترک: کپی از docs/phase5-backup/${TS}/
\`\`\`

## ۸) گام بعد
Gate 5 سبز ⇒ آغاز فاز ۶ (عملیات حمل، هزینهٔ داینامیک، چرخهٔ سه‌مرحله‌ای پرداخت با
دو کلید ضدتکرار، چک‌لیست ۱۰موردی بستن، دفتر طلب) — **پیش از شروع پشتیبان کامل بگیرید (Q10).**
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-5: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

============================================================
 script-05 (005.sh) به پایان رسید
------------------------------------------------------------
 ماژول‌ها      : itr_core (بخش سوم: ریزفاکتور) + itr_transport (اسکلت)
 ریزفاکتور     : فقط پس از امضا (G03) | فقط واحد مالی (5.1) | سقف تناژ (5.3)
 حمل           : ایجاد خودکار idempotent (5.5) | snapshot BR-052 | شمارهٔ فاکتور از ریزفاکتور خودش (5.7)
 رابطه         : Trade Case (1) ──< Sales Slip (1..N) ──< Transport Case (1..N)
 کارتابل       : itr.cartable.mixin (قرارداد فاز ۴) — حمل روی میز سرپرست حمل
 اصلاح‌ها      : FIX-P3-1 / FIX-P4-1 / FIX-P4-2 (ADR-027)
 verify        : ${OPS_DIR}/verify/verify_phase5.py
 گزارش تحویل   : ${DOC_DIR}/PHASE5-DELIVERY.md
 Git           : HEAD=${GIT_HEAD}  tag=phase-5
 گام بعدی      : فاز ۶ (006.sh) — پشتیبان کامل پیش از شروع الزامی است
============================================================
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 5 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۶.${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 5 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۶ آغاز نمی‌شود.${NC}\n"
  exit 1
fi
