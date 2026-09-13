#!/usr/bin/env bash
# =============================================================================
# script-06-transport-operations.sh (006.sh) — PHASE 6 (COMPLETE)
# Iran Trade & Transport ERP — Odoo 19.0 | File-First | Idempotent | Test-First
# Gate-Enforced | No sudo-proof | ★ فاز حساس: Backup اجباری پیش و پس از فاز (Q10)
#
# فاز ۶ — عملیات حمل، هزینهٔ داینامیک، چرخهٔ پرداخت و بستن پرونده : itr_transport
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt ← «فاز ۶» بندهای 6.1..6.16
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۷ (تب‌ها، OPS-021..027،
#       چهار قفل ۷-۴، وضعیت‌های قفل‌شدهٔ ۷-۵)، بخش ۸ (Master/Child، FIN-001..005)،
#       بخش ۹-۳ (چرخهٔ سه‌مرحله‌ای، FIN-021..031)، بخش ۱۰ (چک‌لیست ۱۰موردی، BR-101..123)،
#       G04/G05/G06/G07/G08/G09/G14/G15، DM-105..108، X08/X10/X11/X12/X15/X17
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh … 005.sh همین مخزن.
# اصلاحیهٔ این نسخه (حداقلی، بدون دورزدن هیچ Gate/verify):
#   [FIX-P6-1] تبدیل UniqueViolation ایندکس بارنامه به ValidationError (OPS-021)
#   [FIX-P6-2] ردیف معکوس با state=reversed تا موتور مالی واحد پس از ابطال صفر گزارش کند (FIN-031)
#   + گزارش Traceback کامل تست‌های ناموفق در خروجی Gate (فقط شفافیت، نه تغییر منطق)
#
# پوشش کامل چک‌لیست فاز ۶ (روی اسکلت فاز ۵ — فقط با _inherit و فایل‌های جدید):
#   6.1  itr.transport.case با رابطهٔ N:1 غیر یکتا (فاز ۵) — اثبات دوباره در pg_indexes
#   6.2  فرم چندتبی هم‌زمان: «اسناد بار و ناوگان» (transport_docs) | «مرز و ترخیص»
#        (customs_officer) | «تحویل و تسویه» (transport_delivery) — گارد فیلدمحور سمت
#        سرور به‌ازای هر تب؛ بدون صف ایستگاهی؛ وابستگی فقط اسنادی (بیجک ⇐ بارنامه+باسکول)
#   6.3  راننده/ناوگان با لایهٔ Guarded فاز ۱ (پس از FIX-P3-1) + نمایش سوابق تکراری
#        راننده/پلاک/بارنامه (شمارنده + اکشن تاریخچه؛ OPS-026: رد خودکار نه)
#   6.4  بارنامه: waybill_number یکتا در دامنهٔ (شرکت+صادرکننده) = UNIQUE واقعی
#        (OPS-021)، insurance_amount + گام «تأیید بیمه»، لنگر کرایه (FIN-002)،
#        گام مستقل letter_match_confirmed (X11)
#   6.5  باسکول: خالص=پر−خالی محاسبهٔ خودکار؛ پر<خالی/خالص منفی مسدود (OPS-022)؛ دو
#        مسئول مجزا (ثبت: اسناد | تأیید: مرز)؛ effective_tonnage فقط از باسکول
#        تأییدشده > دستی مستند > هرگز برنامه‌ای (OPS-023)
#   6.6  بیجک شرطی: «نیاز دارد» ⇒ اظهار + بیجک هر دو الزامی (OPS-024)
#   6.7  ★ قفل L1: درخواست صافی کرایه بدون رسید تخلیه در سرور مسدود (G08)
#   6.8  لاگ هماهنگی راننده (تماس/پیامک/تأیید) — فقط لاگ، نه گیت (OPS-005)
#   6.9  itr.charge.type (Master) با category ∈ {freight,customs,clearance,insurance,
#        origin,other} + is_advance/requires_pod/counts_in_freight_anchor + بذر ۶ نوع
#        (گمرک و ترخیص دو رکورد مستقل — G05)
#   6.10 itr.cost.line (Child) با چهار فیلد چندارزی + payee_type/payee_name (Char آزاد)
#        /payee_sheba (Guarded + ماسک VAL-008)
#   6.11 فیلدهای تجمیعی سربرگ فقط‌خواندنی و از موتور مالی واحد (roll-up بر category)
#   6.12 itr.payment.request با کلید A: UNIQUE(company, waybill, payee, charge_type,
#        installment_no) واقعی + پیام «پرداخت تکراری است.» (i18n)
#   6.13 itr.payment.execution با execution_id (UUID) UNIQUE (کلید B)؛ فقط
#        finance_supervisor (L2 / FIN-029)؛ ابطال فقط با رکورد معکوس (FIN-031)
#   6.14 صافی = لنگر − پیش‌کرایهٔ پرداخت‌شده (FIN-021)؛ ضدسرریز Σfreight ≤ لنگر (FIN-022)
#   6.15 چک‌لیست ۱۰موردی Boolean واقعی + chk_payments از «تعهد در برابر تخصیص به تفکیک
#        ارز» (BR-101) + finance_approved با سطح دسترسی مالی؛ بدون ۱۰/۱۰ ⇒ closed مسدود (L3)
#   6.16 بستن دستی با دلیل ⇒ ردیف خودکار itr.factory.shortfall (کلید BR-121 فاز ۴)
#        وقتی مانده≠۰ و اعزام دیگری نیست (BR-111) + تسویهٔ جزئی (BR-122)
#
# پرکردن گپ‌های سند نیازمندی که در نقشهٔ فازی نیامده بودند (دغدغهٔ C3 — همه افزایشی):
#   DM-108 itr.document.type (۱۱ نوع بذر) + itr.transport.document | DM-101 دو مرز
#   غایب فاز ۳ (شلمچه، پرویزخان) | OPS-025 کنترل نوع/حجم رسید تخلیه | FIN-031 ابطال
#   معکوس | BR-123 بازگشایی پروندهٔ بسته با گروه خاص+دلیل | L4 دو پرچم موازی برای
#   settled | OPEN-01/OPEN-02 به‌صورت پارامتر (نه کد) | NOT-031 شش سیاست SLA (قابل
#   ویرایش UI) روی همان موتور فاز ۲ | اعلان‌های گروه B/C/D کاتالوگ که این فاز صدا می‌زند
#
# پوشش دغدغه‌های کارفرما:
#   [C1] سه مالک تب (docs_owner/customs_owner/delivery_owner) + مالک کلی (mixin) —
#        پایهٔ «بارگیری‌های من» فاز ۸؛ ارجاع تب فقط با دلیل و فقط داخل تیم (SEC-004)
#   [C2] هیچ فایل فاز ۳/۴/۵ بازنویسی نمی‌شود: itr.transport.case فقط با _inherit گسترش
#        می‌یابد؛ پچ افزایشی همان فایل‌های مشترک؛ fingerprint قرارداد؛ بازاجرای کامل
#        تست‌های فازهای ۳/۴/۵؛ پشتیبان پیش/پس + آزمون بازیابی واقعی (Gate 6)
#   [C4] هیچ موتور دوم: هزینه/سود از itr.money.engine (با _inherit)، SLA از
#        itr.sla.service، اعلان از notify()، ارز از itr.fx.service
#
# پیش‌نیاز: Gate 5 سبز (bash 005.sh → itr_transport نصب و installed)
#
# استفاده:
#   chmod +x 006.sh
#   bash 006.sh
#
# سوییچ‌ها:
#   SKIP_TESTS=1 / SKIP_VERIFY=1 (Gate قرمز) / SKIP_UAT=1 / START_DAEMON=0
#   SKIP_BACKUP=1        → در این فاز Gate قرمز می‌شود (Q10 اجباری است)
#   SKIP_RESTORE_TEST=1  → Gate قرمز می‌شود (پیوست ج: «شکست Restore یا نبود شاهد»)
#   KEEP_RESTORE_DB=1    → پایگاه‌دادهٔ آزمون بازیابی پاک نشود
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
DB_NAME_RESTORE="${DB_NAME_RESTORE:-odoo19_p6restore}"

HTTP_INTERFACE="${HTTP_INTERFACE:-0.0.0.0}"
HTTP_PORT="${HTTP_PORT:-8069}"

LOG_FILE="${LOG_FILE:-/tmp/odoo19-site-bootstrap.log}"
PID_FILE="${PID_FILE:-/tmp/odoo19-site-bootstrap.pid}"
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase6-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase6-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase6-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase6-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase6-uat.log}"

CORE_MODULE="itr_core"
TRN_MODULE="itr_transport"
CORE_DIR="${CUSTOM_ADDONS}/${CORE_MODULE}"
TRN_DIR="${CUSTOM_ADDONS}/${TRN_MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P6_BACKUP_DIR="${DOC_DIR}/phase6-backup"

SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SKIP_UAT="${SKIP_UAT:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
SKIP_RESTORE_TEST="${SKIP_RESTORE_TEST:-0}"
KEEP_RESTORE_DB="${KEEP_RESTORE_DB:-0}"
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
drop_db() {
  psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${1}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  dropdb "${1}" 2>/dev/null || true
  rm -rf "${DATA_DIR}/filestore/${1}"
}

# =============================================================================
step "0) preflight — Gate 5 سبز + fingerprint قرارداد فازهای ۱..۵ (C2)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
[[ -d "${CORE_DIR}" ]]            || err "ماژول itr_core یافت نشد (ابتدا فاز ۳/۴/۵)"
[[ -d "${TRN_DIR}" ]]             || err "ماژول itr_transport یافت نشد (ابتدا فاز ۵)"
for t in psql git curl ss python3 pg_dump pg_restore createdb dropdb; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G6-00" "نسخهٔ Odoo 19 تأیید شد" "PASS" "${ODOO_V}"
else
  gate "G6-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "${ODOO_V}"; err "فقط Odoo 19."
fi

CORE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TRN_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
SLIP_TBL="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_sales_slip')")"
TRN_TBL="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_transport_case')")"
if [[ "${CORE_STATE}" == "installed" && "${TRN_STATE}" == "installed" && "${SLIP_TBL}" == "itr_sales_slip" && "${TRN_TBL}" == "itr_transport_case" ]]; then
  gate "G6-01" "پیش‌نیازهای فاز ۱..۵ سبز هستند (Q02/Q08)" "PASS" "core/transport=installed"
else
  gate "G6-01" "پیش‌نیازهای فاز ۱..۵ سبز هستند (Q02/Q08)" "FAIL" "core=${CORE_STATE:-?} trn=${TRN_STATE:-?}"
  err "طبق Q08، فازهای ۱ تا ۵ باید پیش از فاز ۶ نصب و سبز باشند."
fi

CONTRACT_FAILS=()
contract() { if grep -qE "$3" "$2" 2>/dev/null; then info "contract OK: $1"; else CONTRACT_FAILS+=("$1 → «$3» در $2 یافت نشد"); fi; }
contract "P1: سرویس Guarded check_sheba"            "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "def check_sheba\("
contract "P1: mask_sheba"                            "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "def mask_sheba\("
contract "P2: notify()"                              "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_service.py" "def notify\(self, event_key, res_model=None, res_id=None, context=None\)"
contract "P2: موتور SLA open_watch"                  "${CUSTOM_ADDONS}/itr_notify/models/itr_sla_service.py" "def open_watch\(self, policy_key, record, owner=None, started_on=None\)"
contract "P2: موتور SLA close_watch"                 "${CUSTOM_ADDONS}/itr_notify/models/itr_sla_service.py" "def close_watch\(self, policy_key, record, reason=None\)"
contract "P2: مدل سیاست SLA"                         "${CUSTOM_ADDONS}/itr_notify/models/itr_sla_policy.py" "_name = \"itr.sla.policy\""
contract "P3: fx apply_fx"                           "${CORE_DIR}/models/itr_fx_service.py" "def apply_fx\(self, amount, from_currency, to_currency=None, date=None\)"
contract "P3: itr.driver"                            "${CORE_DIR}/models/itr_driver.py" "_name = \"itr.driver\""
contract "P3: itr.vehicle"                           "${CORE_DIR}/models/itr_vehicle.py" "_name = \"itr.vehicle\""
contract "P3: itr.border"                            "${CORE_DIR}/models/itr_border.py" "_name = \"itr.border\""
contract "P3: partner flags"                         "${CORE_DIR}/models/itr_partner.py" "is_customs_agent = fields.Boolean"
contract "P4: money engine case_totals"              "${CORE_DIR}/models/money_engine.py" "def case_totals\(self, case\)"
contract "P4: trade case slips_issued→closed"        "${CORE_DIR}/models/itr_trade_case.py" "\"slips_issued\": \{\"closed\"\}"
contract "P4: trade case _do_transition"             "${CORE_DIR}/models/itr_trade_case.py" "def _do_transition\(self, new_state\)"
contract "P4: shortfall model + کلید BR-121"         "${CORE_DIR}/models/itr_factory_shortfall.py" "unique\(trade_case_id, trade_case_item_id\)"
contract "P4: shortfall states"                      "${CORE_DIR}/models/itr_factory_shortfall.py" "\"partially_settled\""
contract "P5: mixin کارتابل"                         "${CORE_DIR}/models/itr_cartable_mixin.py" "_name = \"itr.cartable.mixin\""
contract "P5: TONNAGE_ENGINE_CTX"                    "${CORE_DIR}/models/itr_sales_slip.py" "TONNAGE_ENGINE_CTX = \"itr_tonnage_engine\""
contract "P5: transport case skeleton"               "${TRN_DIR}/models/itr_transport_case.py" "_name = \"itr.transport.case\""
contract "P5: _transition_table() قابل گسترش"        "${TRN_DIR}/models/itr_transport_case.py" "def _transition_table\(self\)"
contract "P5: TRANSPORT_ENGINE_CTX"                  "${TRN_DIR}/models/itr_transport_case.py" "TRANSPORT_ENGINE_CTX = \"itr_transport_state_engine\""
contract "P5: source_item_id"                        "${TRN_DIR}/models/itr_transport_case.py" "source_item_id = fields.Many2one"
contract "P5: 13 state locked"                       "${TRN_DIR}/models/itr_transport_case.py" "\(\"waiting_bijak\", \"Waiting for bijak\"\)"
contract "P5: لنگر manifest itr_transport"           "${TRN_DIR}/__manifest__.py" "views/itr_transport_menus.xml"
contract "P5: فرم پروندهٔ حمل (xmlid)"               "${TRN_DIR}/views/itr_transport_case_views.xml" "id=\"view_itr_transport_case_form\""
contract "P5: تست‌های common"                        "${TRN_DIR}/tests/common.py" "def _handed_over\("
for g in group_transport_supervisor group_transport_docs group_customs_officer group_transport_delivery \
         group_finance_supervisor group_financial_manager group_receivables_user group_ceo group_auditor; do
  GID="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core' AND name='${g}'")"
  [[ "${GID}" == "1" ]] || CONTRACT_FAILS+=("گروه ${g} در دیتابیس یافت نشد")
done
OVR="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_base' AND name='group_itr_validation_override'")"
[[ "${OVR}" == "1" ]] || CONTRACT_FAILS+=("گروه group_itr_validation_override یافت نشد")
if [[ ${#CONTRACT_FAILS[@]} -eq 0 ]]; then
  gate "G6-02" "fingerprint قرارداد فازهای ۱..۵ منطبق است (C2 / پیوست ج)" "PASS" "26 contract + 10 group"
else
  gate "G6-02" "fingerprint قرارداد فازهای ۱..۵ منطبق است (C2 / پیوست ج)" "FAIL" "$(printf '%s | ' "${CONTRACT_FAILS[@]}")"
  err "قرارداد فازهای قبل مطابق فرض فاز ۶ نیست — طبق پیوست ج، فاز متوقف شد. هیچ فایلی تغییر نکرد."
fi

# =============================================================================
step "1) توقف سرویس در حال اجرا"
# =============================================================================
stop_odoo() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
    kill "$(cat "${PID_FILE}")" 2>/dev/null || true; sleep 3
  fi
  pkill -f "odoo-bin.*${CONF_FILE}" 2>/dev/null || true
  sleep 2; rm -f "${PID_FILE}"
}
stop_odoo
port_in_use "${HTTP_PORT}" && warn "پورت ${HTTP_PORT} هنوز listen است" || log "سرویس متوقف شد"

# =============================================================================
step "2) ★ پشتیبان کامل پیش از فاز (Q10 — اجباری) + پشتیبان فایل‌های مشترک"
# =============================================================================
PRE_DUMP=""; PRE_FS=""
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G6-03" "پشتیبان کامل پیش از فاز حساس (Q10)" "FAIL" "SKIP_BACKUP=1 — در فاز ۶ مجاز نیست"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  mapfile -t BK < <(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)
  PRE_DUMP="${BK[0]:-}"; PRE_FS="${BK[1]:-}"
  if [[ -s "${PRE_DUMP:-/nonexistent}" && -f "${PRE_FS:-/nonexistent}" ]]; then
    gate "G6-03" "پشتیبان کامل پیش از فاز حساس (Q10)" "PASS" "$(basename "${PRE_DUMP}") + filestore + sha256"
  else
    gate "G6-03" "پشتیبان کامل پیش از فاز حساس (Q10)" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G6-03" "پشتیبان کامل پیش از فاز حساس (Q10)" "FAIL" "ops/backup.sh یافت نشد (فاز ۰)"
fi

TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${P6_BACKUP_DIR}/${TS}/${TRN_MODULE}"/{models,tests,security,i18n}
for f in "__manifest__.py" "models/__init__.py" "tests/__init__.py" "security/ir.model.access.csv" "i18n/fa_IR.po" "i18n/fa.po"; do
  [[ -f "${TRN_DIR}/${f}" ]] && cp -f "${TRN_DIR}/${f}" "${P6_BACKUP_DIR}/${TS}/${TRN_MODULE}/${f}"
done
log "کپی امن فایل‌های مشترک itr_transport در ${P6_BACKUP_DIR}/${TS}"

# =============================================================================
step "3) فایل‌های *جدید* itr_transport (هیچ فایل فاز ۵ بازنویسی نمی‌شود — C2)"
# =============================================================================
mkdir -p "${TRN_DIR}"/{models,security,data,views,i18n,tests}
find "${TRN_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

# ----------------------------------------------- models/itr_charge_type.py --
write_utf8 "${TRN_DIR}/models/itr_charge_type.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Charge type MASTER (checklist 6.9 / SRS 8-1 / G05 / G06 / G09).

Adding a new cost (demurrage, border parking, overweight, ...) is DATA, never
code: the code depends ONLY on `category`, never on the Persian name.
Customs duty (customs) and clearance fee (clearance) are two independent
categories and are never merged into one record (G05).
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

CHARGE_CATEGORIES = [
    ("freight", "Freight"),
    ("customs", "Customs duty (government)"),
    ("clearance", "Clearance fee (broker / border agent)"),
    ("insurance", "Cargo insurance"),
    ("origin", "Origin / factory door"),
    ("other", "Other"),
]
PAYEE_TYPES = [
    ("driver", "Driver"),
    ("carrier", "Carrier"),
    ("broker", "Customs broker"),
    ("customs", "Customs office"),
    ("insurer", "Insurer"),
    ("other", "Other"),
]
CALC_MODES = [("fixed", "Fixed amount"), ("per_ton", "Per ton"), ("percent", "Percent")]


class ItrChargeType(models.Model):
    _name = "itr.charge.type"
    _description = "Transport Charge Type"
    _order = "sequence, name"

    name = fields.Char(string="Charge name", required=True, translate=True)
    code = fields.Char(string="Technical code", required=True, index=True)
    category = fields.Selection(CHARGE_CATEGORIES, string="Category", required=True,
                                help="The ONLY thing the code depends on (SRS 8-1).")
    sequence = fields.Integer(string="Sequence", default=10)
    active = fields.Boolean(string="Active", default=True)
    is_advance = fields.Boolean(string="Advance (paid at origin, needs the waybill)")
    requires_pod = fields.Boolean(string="Requires the delivery receipt (POD lock, G08)")
    counts_in_freight_anchor = fields.Boolean(string="Counts against the waybill freight anchor")
    payee_type = fields.Selection(PAYEE_TYPES, string="Default payee type", default="other")
    calc_mode = fields.Selection(CALC_MODES, string="Calculation mode", default="fixed")
    default_currency_id = fields.Many2one("res.currency", string="Default currency")
    allowed_currency_ids = fields.Many2many("res.currency", string="Allowed currencies")
    valid_from = fields.Date(string="Valid from")
    valid_to = fields.Date(string="Valid to")
    is_seed = fields.Boolean(string="Created by the installer", readonly=True)
    note = fields.Text(string="Notes")

    _code_uniq = models.Constraint("unique(code)", "The charge type code must be unique.")

    @api.constrains("category", "is_advance", "requires_pod", "counts_in_freight_anchor")
    def _check_category_flags(self):
        for record in self:
            if record.category != "freight" and (record.is_advance or record.counts_in_freight_anchor):
                raise ValidationError(
                    _("Only a freight charge can be an advance or count against the freight anchor."))

    def unlink(self):
        for record in self:
            if self.env["itr.cost.line"].sudo().search_count([("charge_type_id", "=", record.id)]):  # ITR-SUDO-OK existence check
                raise ValidationError(_("A charge type in use cannot be deleted; archive it (DM-120)."))
        return super().unlink()
PYEOF

# --------------------------------------------- models/itr_document_type.py --
write_utf8 "${TRN_DIR}/models/itr_document_type.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Document type master (SRS DM-108 - gap of the phased plan, filled here)
+ the attachment rows of a transport case (OPS-025 type/size guards)."""
import base64

from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

ALLOWED_EXTENSIONS = ("pdf", "jpg", "jpeg", "png")


def validate_upload(env, filename, content_b64, label):
    """OPS-025: extension + size guard shared by every upload path."""
    name = (filename or "").lower()
    if not name or "." not in name or name.rsplit(".", 1)[1] not in ALLOWED_EXTENSIONS:
        raise ValidationError(
            _("%(label)s must be a PDF / JPG / PNG file (OPS-025). Received: %(name)s",
              label=label, name=filename or "-"))
    max_mb = float(env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
        "itr_transport.upload_max_mb", "10"))
    try:
        size = len(base64.b64decode(content_b64 or b""))
    except Exception:  # noqa: BLE001
        size = 0
    if size > max_mb * 1024 * 1024:
        raise ValidationError(
            _("%(label)s exceeds the maximum size of %(mb)s MB (OPS-025).", label=label, mb=max_mb))
    return True


class ItrDocumentType(models.Model):
    _name = "itr.document.type"
    _description = "Document Type"
    _order = "sequence, name"

    name = fields.Char(string="Name", required=True, translate=True)
    code = fields.Char(string="Code", required=True, index=True)
    sequence = fields.Integer(string="Sequence", default=10)
    active = fields.Boolean(string="Active", default=True)
    is_financial = fields.Boolean(
        string="Financial document",
        help="SEC-014: financial attachments are hidden from operational groups (phase 7).")
    is_seed = fields.Boolean(string="Created by the installer", readonly=True)

    _code_uniq = models.Constraint("unique(code)", "The document type code must be unique.")


class ItrTransportDocument(models.Model):
    _name = "itr.transport.document"
    _description = "Transport Case Document"
    _order = "id desc"

    transport_case_id = fields.Many2one("itr.transport.case", string="Transport case",
                                        required=True, ondelete="cascade", index=True)
    document_type_id = fields.Many2one("itr.document.type", string="Document type", required=True)
    is_financial = fields.Boolean(related="document_type_id.is_financial", store=True)
    file = fields.Binary(string="File", attachment=True, required=True)
    filename = fields.Char(string="File name", required=True)
    uploaded_by_id = fields.Many2one("res.users", string="Uploaded by", readonly=True,
                                     default=lambda self: self.env.user)
    uploaded_on = fields.Datetime(string="Uploaded on", readonly=True, default=fields.Datetime.now)
    note = fields.Char(string="Note")

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            validate_upload(self.env, vals.get("filename"), vals.get("file"), _("Document"))
        return super().create(vals_list)

    def write(self, vals):
        if "file" in vals or "filename" in vals:
            for record in self:
                validate_upload(self.env, vals.get("filename", record.filename),
                                vals.get("file", record.file), _("Document"))
        return super().write(vals)

    def unlink(self):
        raise UserError(_("Documents are never deleted from a transport case (OPS-027); archive the case instead."))
PYEOF

# ------------------------------------------------- models/itr_cost_line.py --
write_utf8 "${TRN_DIR}/models/itr_cost_line.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Cost line CHILD (checklist 6.10 / SRS 8-2 / G06 / G12 / FIN-002 / FIN-014).

A cost line is a COMMITMENT (ledger of costs). It is never a payment (G07):
the payment request and the payment execution are separate models and the
money engine never counts a payment as a second cost (FIN-003).
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

from .itr_charge_type import PAYEE_TYPES

PAYMENT_STATUSES = [
    ("recorded", "Recorded"),
    ("requested", "Payment requested"),
    ("paid", "Paid"),
    ("rejected", "Rejected"),
]
PAYMENT_ENGINE_CTX = "itr_payment_engine"

LINE_CREATOR_GROUPS = (
    "itr_core.group_transport_docs", "itr_core.group_customs_officer",
    "itr_core.group_transport_delivery", "itr_core.group_transport_supervisor",
    "itr_core.group_finance_supervisor", "itr_core.group_ceo",
)
CATEGORY_GROUPS = {
    "customs": ("itr_core.group_customs_officer", "itr_core.group_transport_supervisor",
                "itr_core.group_finance_supervisor", "itr_core.group_ceo"),
    "clearance": ("itr_core.group_customs_officer", "itr_core.group_transport_supervisor",
                  "itr_core.group_finance_supervisor", "itr_core.group_ceo"),
    "freight": ("itr_core.group_transport_delivery", "itr_core.group_transport_docs",
                "itr_core.group_transport_supervisor", "itr_core.group_finance_supervisor",
                "itr_core.group_ceo"),
}


class ItrCostLine(models.Model):
    _name = "itr.cost.line"
    _description = "Transport Cost Line"
    _order = "transport_case_id, id"

    transport_case_id = fields.Many2one("itr.transport.case", string="Transport case",
                                        required=True, ondelete="cascade", index=True)
    company_id = fields.Many2one(related="transport_case_id.company_id", store=True, readonly=True)
    charge_type_id = fields.Many2one("itr.charge.type", string="Charge type", required=True,
                                     ondelete="restrict", domain=[("active", "=", True)])
    category = fields.Selection(related="charge_type_id.category", store=True, readonly=True, index=True)
    is_advance = fields.Boolean(related="charge_type_id.is_advance", store=True, readonly=True)
    requires_pod = fields.Boolean(related="charge_type_id.requires_pod", store=True, readonly=True)
    counts_in_freight_anchor = fields.Boolean(related="charge_type_id.counts_in_freight_anchor",
                                              store=True, readonly=True)
    description = fields.Char(string="Description")

    # --- G12: four standard money-event fields + lock ------------------------
    amount = fields.Float(string="Amount", required=True)
    currency_id = fields.Many2one("res.currency", string="Currency", required=True,
                                  default=lambda self: self.env.company.currency_id)
    exchange_rate = fields.Float(string="Conversion rate", readonly=True)
    base_amount = fields.Float(string="Base amount (IRR)", readonly=True)
    rate_locked = fields.Boolean(string="Rate locked", readonly=True)

    # --- payee (never a mandatory link to a user) ----------------------------
    payee_type = fields.Selection(PAYEE_TYPES, string="Payee type", required=True, default="other")
    payee_name = fields.Char(string="Payee name", required=True,
                             help="Free text: a driver or a foreign exchange office may have no account.")
    payee_sheba = fields.Char(string="Payee SHEBA")
    payee_sheba_masked = fields.Char(string="Payee SHEBA (masked)", compute="_compute_sheba_masked")
    payee_bank = fields.Char(string="Payee bank")
    installment_no = fields.Integer(string="Installment no.", default=1,
                                    help="FIN-023: legitimate partial payments use a new installment number.")

    payment_status = fields.Selection(PAYMENT_STATUSES, string="Payment status", required=True,
                                      default="recorded", readonly=True, index=True)
    payment_request_id = fields.Many2one("itr.payment.request", string="Payment request", readonly=True)
    attachment_ids = fields.Many2many("ir.attachment", string="Attachments")
    recorded_by_id = fields.Many2one("res.users", string="Recorded by", readonly=True,
                                     default=lambda self: self.env.user)
    recorded_on = fields.Datetime(string="Recorded on", readonly=True, default=fields.Datetime.now)

    @api.depends("payee_sheba")
    def _compute_sheba_masked(self):
        service = self.env["itr.validation.service"]
        for line in self:
            line.payee_sheba_masked = service.mask_sheba(line.payee_sheba) if line.payee_sheba else ""

    # --------------------------------------------------------------- guards
    def _check_creator(self, category):
        if self.env.su:
            raise UserError(_("Cost lines are never recorded as superuser (G01/Q03)."))
        user = self.env.user
        groups = CATEGORY_GROUPS.get(category, LINE_CREATOR_GROUPS)
        if not any(user.has_group(g) for g in groups):
            raise UserError(
                _("Your role may not record a cost of category '%(c)s' (SRS 4-3 capability matrix).",
                  c=category))

    @api.constrains("amount")
    def _check_amount(self):
        for line in self:
            if line.amount <= 0:
                raise ValidationError(_("A cost amount must be greater than zero."))

    @api.constrains("payee_sheba")
    def _check_payee_sheba(self):
        service = self.env["itr.validation.service"]
        for line in self:
            if line.payee_sheba:
                service.check_sheba(line.payee_sheba, res_model=self._name, res_id=line.id)

    @api.constrains("installment_no")
    def _check_installment(self):
        for line in self:
            if line.installment_no < 1:
                raise ValidationError(_("The installment number starts at 1."))

    @api.constrains("charge_type_id", "currency_id")
    def _check_allowed_currency(self):
        for line in self:
            allowed = line.charge_type_id.allowed_currency_ids
            if allowed and line.currency_id not in allowed:
                raise ValidationError(
                    _("Currency %(c)s is not allowed for charge type %(t)s.",
                      c=line.currency_id.name, t=line.charge_type_id.name))

    @api.constrains("base_amount", "category", "counts_in_freight_anchor", "payment_status", "transport_case_id")
    def _check_freight_anchor(self):
        """FIN-002: sum of freight lines <= waybill total freight (the anchor)."""
        for case in self.mapped("transport_case_id"):
            anchor = case.waybill_freight_base
            if anchor <= 0:
                continue
            total = sum(case.cost_line_ids.filtered(
                lambda l: l.category == "freight" and l.counts_in_freight_anchor
                and l.payment_status != "rejected").mapped("base_amount"))
            if total > anchor + 0.5:
                raise ValidationError(
                    _("The freight cost lines (%(t)s IRR) exceed the waybill freight anchor "
                      "(%(a)s IRR) of loading %(n)s (FIN-002). The waybill only sets the ceiling.",
                      t=total, a=anchor, n=case.name))

    @api.model_create_multi
    def create(self, vals_list):
        fx = self.env["itr.fx.service"]
        for vals in vals_list:
            charge = self.env["itr.charge.type"].browse(vals.get("charge_type_id"))
            self._check_creator(charge.category)
            case = self.env["itr.transport.case"].browse(vals.get("transport_case_id"))
            if case.state in ("closed", "cancelled"):
                raise UserError(_("No cost can be recorded on a closed or cancelled loading."))
            if charge.category == "freight" and not case.waybill_number:
                raise UserError(_("Freight costs need the waybill first (SRS 9-3, stage 1)."))
            if not vals.get("currency_id"):
                vals["currency_id"] = (charge.default_currency_id or self.env.company.currency_id).id
            if not vals.get("payee_type"):
                vals["payee_type"] = charge.payee_type or "other"
            # FIN-014: every money event locks its own rate when it happens
            currency = self.env["res.currency"].browse(vals["currency_id"])
            result = fx.apply_fx(vals.get("amount", 0.0), currency)
            vals.update({"exchange_rate": result["conversion_rate"],
                         "base_amount": result["base_amount"], "rate_locked": True})
        return super().create(vals_list)

    def write(self, vals):
        engine = self.env.context.get(PAYMENT_ENGINE_CTX)
        if ("payment_status" in vals or "payment_request_id" in vals) and not engine:
            raise UserError(_("The payment status of a cost line is written only by the payment engine."))
        frozen = {"amount", "currency_id", "charge_type_id", "payee_name", "installment_no"}
        if frozen & set(vals) and not engine:
            for line in self:
                if line.payment_status != "recorded":
                    raise UserError(_("A cost line with a payment request is frozen (FIN-014)."))
        return super().write(vals)

    def unlink(self):
        for line in self:
            if line.payment_status != "recorded":
                raise UserError(_("A cost line with a payment request cannot be deleted (FIN-031)."))
        return super().unlink()

    # -------------------------------------------------------- payment cycle
    def action_request_payment(self):
        """Stage 1/2/3 of the payment cycle (SRS 9-3) - creates the REQUEST."""
        Request = self.env["itr.payment.request"]
        created = Request
        for line in self:
            self._check_creator(line.category)
            case = line.transport_case_id
            if line.payment_status != "recorded":
                raise UserError(_("Cost line '%(d)s' already has a payment request.", d=line.display_name))
            if not case.waybill_number:
                raise UserError(_("A payment request needs the waybill number (key A, FIN-023)."))
            # ★ L1 / G08: final freight is locked until the delivery receipt is uploaded
            if line.requires_pod and not case.delivery_receipt:
                raise UserError(
                    _("The final freight settlement of loading %(n)s is locked until the buyer's "
                      "delivery receipt (POD) is uploaded (G08 / lock L1).", n=case.name))
            if line.is_advance and not case.waybill_number:
                raise UserError(_("The advance freight depends on the waybill (SRS 9-3 stage 1)."))
            docs_review = self.env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
                "itr_transport.payment_docs_review_required", "0") == "1"
            if docs_review and line.category == "freight" and not case.docs_reviewed_payment:
                raise UserError(
                    _("Policy OPEN-01 is active: the fleet & documents specialist must review "
                      "the payment before it is requested."))
            request = Request._create_from_cost_line(line)
            line.with_context(**{PAYMENT_ENGINE_CTX: True}).write({
                "payment_status": "requested", "payment_request_id": request.id})
            created |= request
        return created
PYEOF

# ------------------------------------------- models/itr_payment_request.py --
write_utf8 "${TRN_DIR}/models/itr_payment_request.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Payment REQUEST (checklist 6.12 / SRS 9-3 / G04 / G07 / FIN-023..028).

Key A - a REAL PostgreSQL unique index:
    UNIQUE(company_id, waybill_number, payee_name, charge_type_id, installment_no)
    WHERE state != 'rejected'
The amount is never part of the key; the driver is never part of the key
(FIN-025/026). A request never enters the execution table (FIN-028).
"""
import psycopg2

from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

REQUEST_STATES = [
    ("requested", "Requested"),
    ("executed", "Executed"),
    ("rejected", "Rejected"),
]
REQUEST_ENGINE_CTX = "itr_payment_engine"
KEY_A_INDEX = "itr_payment_request_key_a_uniq"


class ItrPaymentRequest(models.Model):
    _name = "itr.payment.request"
    _description = "Payment Request"
    _inherit = ["mail.thread", "mail.activity.mixin", "itr.cartable.mixin"]
    _order = "id desc"

    name = fields.Char(string="Request number", required=True, copy=False, readonly=True,
                       index=True, default=lambda self: _("New"))
    company_id = fields.Many2one("res.company", string="Company", required=True, index=True,
                                 default=lambda self: self.env.company)
    transport_case_id = fields.Many2one("itr.transport.case", string="Transport case", required=True,
                                        ondelete="restrict", index=True)
    cost_line_id = fields.Many2one("itr.cost.line", string="Cost line", required=True,
                                   ondelete="restrict", index=True)
    charge_type_id = fields.Many2one("itr.charge.type", string="Charge type", required=True, readonly=True)
    category = fields.Selection(related="charge_type_id.category", store=True, readonly=True)
    is_advance = fields.Boolean(related="charge_type_id.is_advance", store=True, readonly=True)
    counts_in_freight_anchor = fields.Boolean(related="charge_type_id.counts_in_freight_anchor",
                                              store=True, readonly=True)
    # ---- key A components (snapshot at request time) -------------------------
    waybill_number = fields.Char(string="Waybill number", required=True, readonly=True, index=True)
    payee_name = fields.Char(string="Payee", required=True, readonly=True, index=True)
    payee_sheba = fields.Char(string="Payee SHEBA", readonly=True)
    payee_sheba_masked = fields.Char(string="Payee SHEBA (masked)", compute="_compute_sheba_masked")
    installment_no = fields.Integer(string="Installment no.", required=True, default=1, readonly=True)
    # ---- money event -----------------------------------------------------------
    amount = fields.Float(string="Amount", required=True, readonly=True)
    currency_id = fields.Many2one("res.currency", string="Currency", required=True, readonly=True)
    exchange_rate = fields.Float(string="Conversion rate (at request)", readonly=True)
    base_amount = fields.Float(string="Base amount (IRR, at request)", readonly=True)

    state = fields.Selection(REQUEST_STATES, string="State", required=True, default="requested",
                             index=True, tracking=True, copy=False)
    requested_by_id = fields.Many2one("res.users", string="Requested by", readonly=True,
                                      default=lambda self: self.env.user)
    requested_on = fields.Datetime(string="Requested on", readonly=True, default=fields.Datetime.now)
    reject_reason = fields.Text(string="Rejection reason", readonly=True)
    execution_ids = fields.One2many("itr.payment.execution", "payment_request_id", string="Executions")
    executed_base_amount = fields.Float(string="Executed (IRR)", compute="_compute_executed", store=True)
    note = fields.Text(string="Notes")

    def init(self):
        """Key A as a REAL partial unique index (rejected requests may be re-issued)."""
        self.env.cr.execute("SELECT 1 FROM pg_indexes WHERE indexname = %s", (KEY_A_INDEX,))
        if not self.env.cr.fetchone():
            self.env.cr.execute(
                'CREATE UNIQUE INDEX "%s" ON "%s" '
                "(company_id, waybill_number, payee_name, charge_type_id, installment_no) "
                "WHERE state != 'rejected'" % (KEY_A_INDEX, self._table))

    @api.depends("payee_sheba")
    def _compute_sheba_masked(self):
        service = self.env["itr.validation.service"]
        for record in self:
            record.payee_sheba_masked = service.mask_sheba(record.payee_sheba) if record.payee_sheba else ""

    @api.depends("execution_ids.base_amount", "execution_ids.state")
    def _compute_executed(self):
        for record in self:
            record.executed_base_amount = sum(
                record.execution_ids.filtered(lambda e: e.state == "done").mapped("base_amount"))

    # --------------------------------------------------------------- guards
    @api.model_create_multi
    def create(self, vals_list):
        if not self.env.context.get(REQUEST_ENGINE_CTX):
            raise UserError(
                _("A payment request is created only from a cost line "
                  "(action 'Request payment'), never by hand (G07)."))
        for vals in vals_list:
            if not vals.get("name") or vals.get("name") == _("New"):
                vals["name"] = self.env["ir.sequence"].next_by_code("itr.payment.request") or _("New")
        try:
            with self.env.cr.savepoint():
                records = super().create(vals_list)
        except psycopg2.IntegrityError as error:
            if KEY_A_INDEX in str(error) or "unique" in str(error).lower():
                raise ValidationError(_("Duplicate payment request (key A: waybill / payee / charge type / installment)."))
            raise
        return records

    def write(self, vals):
        if "state" in vals and not self.env.context.get(REQUEST_ENGINE_CTX):
            raise UserError(_("The state of a payment request changes only through its official actions."))
        return super().write(vals)

    def unlink(self):
        raise UserError(_("Payment requests are never deleted; reject them with a reason (FIN-031)."))

    @api.model
    def _create_from_cost_line(self, line):
        case = line.transport_case_id
        request = self.with_context(**{REQUEST_ENGINE_CTX: True}).create({
            "company_id": case.company_id.id,
            "transport_case_id": case.id,
            "cost_line_id": line.id,
            "charge_type_id": line.charge_type_id.id,
            "waybill_number": case.waybill_number,
            "payee_name": (line.payee_name or "").strip(),
            "payee_sheba": line.payee_sheba,
            "installment_no": line.installment_no,
            "amount": line.amount,
            "currency_id": line.currency_id.id,
            "exchange_rate": line.exchange_rate,
            "base_amount": line.base_amount,
        })
        request._hand_over_to_group("itr_core.group_finance_supervisor",
                                    _("Review and execute the payment request"))
        request._itr_notify("payment.requested", {"amount": line.amount, "payee": line.payee_name})
        return request

    # -------------------------------------------------------------- actions
    def _require_finance_supervisor(self, action):
        if self.env.su:
            raise UserError(_("Business transitions are never executed as superuser (G01/Q03)."))
        if not self.env.user.has_group("itr_core.group_finance_supervisor"):
            raise UserError(
                _("Only the finance supervisor may %(a)s a payment (lock L2 / FIN-029).", a=action))

    def action_reject(self, reason=None):
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        self._require_finance_supervisor(_("reject"))
        if not reason:
            raise UserError(_("Rejecting a payment request requires a mandatory reason."))
        for request in self:
            if request.state != "requested":
                raise UserError(_("Only a pending request can be rejected."))
            request.with_context(**{REQUEST_ENGINE_CTX: True}).write(
                {"state": "rejected", "reject_reason": reason, "current_owner_id": False})
            request.cost_line_id.with_context(**{REQUEST_ENGINE_CTX: True}).write(
                {"payment_status": "rejected"})
            request._itr_notify("payment.rejected", {"reason": reason})
            request.message_post(body=_("Payment request rejected. Reason: %(r)s", r=reason))
        return True

    def action_execute(self, bank_reference=None, execution_id=None, receipt=None, receipt_name=None):
        """The definitive payment (lock L2). Creates the EXECUTION row (key B)."""
        self._require_finance_supervisor(_("execute"))
        Execution = self.env["itr.payment.execution"]
        fx = self.env["itr.fx.service"]
        created = Execution
        for request in self:
            if request.state != "requested":
                raise UserError(_("Request %(n)s is not pending (state %(s)s); a second execution is refused.",
                                  n=request.name, s=request.state))
            if request.requested_by_id == self.env.user:
                raise UserError(_("Segregation of duties: the requester cannot execute his own payment (SEC-015)."))
            case = request.transport_case_id
            # FIN-014: the execution locks ITS OWN rate at the moment it happens
            result = fx.apply_fx(request.amount, request.currency_id)
            base_amount = result["base_amount"]
            # FIN-022: anti-overflow against the waybill freight anchor
            if request.category == "freight" and request.counts_in_freight_anchor and case.waybill_freight_base > 0:
                if case.freight_settled_base + base_amount > case.waybill_freight_base + 0.5:
                    raise UserError(
                        _("Executing this freight payment would exceed the waybill freight anchor of "
                          "loading %(n)s (%(paid)s + %(new)s > %(anchor)s IRR) - FIN-022.",
                          n=case.name, paid=case.freight_settled_base, new=base_amount,
                          anchor=case.waybill_freight_base))
            vals = {
                "payment_request_id": request.id,
                "amount": request.amount,
                "currency_id": request.currency_id.id,
                "exchange_rate": result["conversion_rate"],
                "base_amount": base_amount,
                "bank_reference": bank_reference or self.env.context.get("itr_bank_reference"),
                "receipt_file": receipt,
                "receipt_filename": receipt_name,
            }
            if execution_id:
                vals["execution_id"] = execution_id
            execution = Execution.with_context(**{REQUEST_ENGINE_CTX: True}).create(vals)
            request.with_context(**{REQUEST_ENGINE_CTX: True}).write(
                {"state": "executed", "current_owner_id": False})
            request.cost_line_id.with_context(**{REQUEST_ENGINE_CTX: True}).write(
                {"payment_status": "paid"})
            request._itr_notify("payment.executed", {"amount": request.amount, "payee": request.payee_name})
            request.message_post(body=_("Payment executed (execution %(e)s).", e=execution.execution_id))
            created |= execution
        return created
PYEOF

# ----------------------------------------- models/itr_payment_execution.py --
write_utf8 "${TRN_DIR}/models/itr_payment_execution.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Payment EXECUTION (checklist 6.13 / G04 key B / FIN-024 / FIN-029 / FIN-031).

* execution_id (UUID) is a REAL database unique key - a double click, a retried
  RPC or two workers can never produce two executions of the same identifier.
* Only the finance supervisor may create a row (lock L2 / FIN-029): the
  transport specialist can never mark his own line as paid.
* Append-only: cancellation is a REVERSAL row, never a delete (FIN-031).
"""
import uuid

from odoo import _, api, fields, models
from odoo.exceptions import UserError

EXECUTION_STATES = [("done", "Done"), ("reversed", "Reversed")]
ENGINE_CTX = "itr_payment_engine"


class ItrPaymentExecution(models.Model):
    _name = "itr.payment.execution"
    _description = "Payment Execution"
    _order = "id desc"

    execution_id = fields.Char(string="Execution id (UUID)", required=True, readonly=True, index=True,
                               default=lambda self: str(uuid.uuid4()))
    payment_request_id = fields.Many2one("itr.payment.request", string="Payment request", required=True,
                                         ondelete="restrict", index=True)
    transport_case_id = fields.Many2one(related="payment_request_id.transport_case_id", store=True,
                                        index=True, readonly=True)
    company_id = fields.Many2one(related="payment_request_id.company_id", store=True, readonly=True)
    charge_type_id = fields.Many2one(related="payment_request_id.charge_type_id", store=True, readonly=True)
    category = fields.Selection(related="payment_request_id.category", store=True, readonly=True)
    is_advance = fields.Boolean(related="payment_request_id.is_advance", store=True, readonly=True)
    counts_in_freight_anchor = fields.Boolean(related="payment_request_id.counts_in_freight_anchor",
                                              store=True, readonly=True)
    payee_name = fields.Char(related="payment_request_id.payee_name", store=True, readonly=True)
    payee_sheba_masked = fields.Char(related="payment_request_id.payee_sheba_masked", readonly=True)

    amount = fields.Float(string="Amount", required=True, readonly=True)
    currency_id = fields.Many2one("res.currency", string="Currency", required=True, readonly=True)
    exchange_rate = fields.Float(string="Conversion rate (at execution)", readonly=True)
    base_amount = fields.Float(string="Base amount (IRR)", readonly=True)
    rate_locked = fields.Boolean(string="Rate locked", default=True, readonly=True)

    bank_reference = fields.Char(string="Bank tracking reference", readonly=True)
    receipt_file = fields.Binary(string="Bank receipt", attachment=True, readonly=True)
    receipt_filename = fields.Char(string="Receipt file name", readonly=True)
    executed_by_id = fields.Many2one("res.users", string="Executed by", required=True, readonly=True,
                                     default=lambda self: self.env.user)
    executed_on = fields.Datetime(string="Executed on", required=True, readonly=True,
                                  default=fields.Datetime.now)
    state = fields.Selection(EXECUTION_STATES, string="State", required=True, default="done", readonly=True)
    is_reversal = fields.Boolean(string="Reversal row", readonly=True)
    reversed_execution_id = fields.Many2one("itr.payment.execution", string="Reverses", readonly=True)
    reversal_reason = fields.Text(string="Reversal reason", readonly=True)

    # key B (ADR-022: models.Constraint)
    _execution_id_uniq = models.Constraint(
        "unique(execution_id)",
        "Duplicate payment execution (key B: execution id).",
    )

    @api.model_create_multi
    def create(self, vals_list):
        if self.env.su:
            raise UserError(_("Payments are never executed as superuser (G01/Q03)."))
        if not self.env.user.has_group("itr_core.group_finance_supervisor"):
            raise UserError(_("Only the finance supervisor may record a definitive payment (FIN-029)."))
        if not self.env.context.get(ENGINE_CTX):
            raise UserError(_("A payment execution is created only through the request's execute action."))
        return super().create(vals_list)

    def write(self, vals):
        allowed = {"state"}
        if not self.env.context.get(ENGINE_CTX) or set(vals) - allowed:
            raise UserError(_("Payment executions are append-only (FIN-031)."))
        return super().write(vals)

    def unlink(self):
        raise UserError(_("Payment executions are never deleted; record a reversal instead (FIN-031)."))

    def action_reverse(self, reason=None):
        """FIN-031: cancellation = a negative reversal row."""
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        if self.env.su or not self.env.user.has_group("itr_core.group_finance_supervisor"):
            raise UserError(_("Only the finance supervisor may reverse a payment (FIN-029)."))
        if not reason:
            raise UserError(_("Reversing a payment requires a mandatory reason."))
        reversals = self.browse()
        for execution in self:
            if execution.state != "done" or execution.is_reversal:
                raise UserError(_("Only a done, non-reversal execution can be reversed."))
            reversal = self.with_context(**{ENGINE_CTX: True}).create({
                "payment_request_id": execution.payment_request_id.id,
                "amount": -execution.amount,
                "currency_id": execution.currency_id.id,
                "exchange_rate": execution.exchange_rate,
                "base_amount": -execution.base_amount,
                "is_reversal": True,
                # [FIX-P6-2] FIN-031: the reversed pair leaves the settled ledger
                # TOGETHER, so the single money engine (state == "done") reports 0
                # after a reversal instead of a negative double-count (test_26 FAIL).
                "state": "reversed",
                "reversed_execution_id": execution.id,
                "reversal_reason": reason,
                "bank_reference": execution.bank_reference,
            })
            execution.with_context(**{ENGINE_CTX: True}).write({"state": "reversed"})
            request = execution.payment_request_id
            request.with_context(**{ENGINE_CTX: True}).write({"state": "requested"})
            request.cost_line_id.with_context(**{ENGINE_CTX: True}).write({"payment_status": "requested"})
            request._hand_over_to_group("itr_core.group_finance_supervisor",
                                        _("Payment reversed - request pending again"))
            request.message_post(body=_("Execution %(e)s reversed. Reason: %(r)s",
                                        e=execution.execution_id, r=reason))
            reversals |= reversal
        return reversals
PYEOF

# ------------------------------------ models/itr_driver_coordination_log.py --
write_utf8 "${TRN_DIR}/models/itr_driver_coordination_log.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Driver coordination log (checklist 6.8 / OPS-005): a call, an SMS or a
driver confirmation is INFORMATION, never a physical gate."""
from odoo import fields, models

KINDS = [("call", "Phone call"), ("sms", "SMS"), ("driver_confirmed", "Driver confirmed"), ("note", "Note")]


class ItrDriverCoordinationLog(models.Model):
    _name = "itr.driver.coordination.log"
    _description = "Driver Coordination Log"
    _order = "id desc"

    transport_case_id = fields.Many2one("itr.transport.case", string="Transport case", required=True,
                                        ondelete="cascade", index=True)
    kind = fields.Selection(KINDS, string="Kind", required=True, default="call")
    note = fields.Char(string="Note", required=True)
    logged_by_id = fields.Many2one("res.users", string="Logged by", readonly=True,
                                   default=lambda self: self.env.user)
    logged_on = fields.Datetime(string="Logged on", readonly=True, default=fields.Datetime.now)
PYEOF

# ------------------------------------------------- models/money_engine.py --
write_utf8 "${TRN_DIR}/models/money_engine.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase-6 extension of THE single money engine (checklist 6.11 / SRS 8-4).

Still one engine (G18 / FIN-005): this file only adds the transport
operational cost and the settlement figures BY INHERITANCE and feeds them
into case_totals(). Cost comes from itr.cost.line (commitment), settlement
from itr.payment.execution (cash) - never mixed (FIN-003 / REP-005).
"""
from odoo import api, models

COST_CATEGORIES = ("freight", "customs", "clearance", "insurance", "origin", "other")


class ItrMoneyEngine(models.AbstractModel):
    _inherit = "itr.money.engine"

    @api.model
    def transport_totals(self, transport_case):
        """The one and only financial summary of a loading."""
        by_category = {category: 0.0 for category in COST_CATEGORIES}
        for line in transport_case.cost_line_ids:
            if line.payment_status == "rejected":
                continue
            by_category[line.category or "other"] = by_category.get(line.category or "other", 0.0) + line.base_amount
        total_cost = sum(by_category.values())
        executions = transport_case.payment_execution_ids.filtered(lambda e: e.state == "done")
        total_settled = sum(executions.mapped("base_amount"))
        freight_settled = sum(executions.filtered(
            lambda e: e.category == "freight" and e.counts_in_freight_anchor).mapped("base_amount"))
        advance_paid = sum(executions.filtered(lambda e: e.is_advance).mapped("base_amount"))
        anchor = transport_case.waybill_freight_base or 0.0
        # FIN-021: final freight = anchor - advances actually paid
        final_freight_due = max(0.0, anchor - advance_paid) if anchor else 0.0
        return {
            "freight_cost": by_category["freight"],
            "customs_cost": by_category["customs"],
            "clearance_cost": by_category["clearance"],
            "insurance_cost": by_category["insurance"],
            "origin_cost": by_category["origin"],
            "other_cost": by_category["other"],
            "total_cost": total_cost,
            "total_settled": total_settled,
            "freight_settled": freight_settled,
            "advance_paid": advance_paid,
            "final_freight_due": final_freight_due,
        }

    @api.model
    def case_totals(self, case):
        totals = super().case_totals(case)
        operational_cost = 0.0
        total_settled = 0.0
        loadings = case.transport_case_ids.filtered(lambda t: t.state != "cancelled") \
            if "transport_case_ids" in case._fields else case.env["itr.transport.case"]
        for loading in loadings:
            figures = self.transport_totals(loading)
            operational_cost += figures["total_cost"]
            total_settled += figures["total_settled"]
        # FIN-004: costs live on the loadings only - nothing is counted twice
        totals["operational_cost"] = operational_cost
        totals["total_settled"] = total_settled
        totals["estimated_profit"] = totals["sales_base"] - totals["purchase_base"] - operational_cost
        return totals
PYEOF

# --------------------------------------- models/itr_transport_case_ops.py --
write_utf8 "${TRN_DIR}/models/itr_transport_case_ops.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase-6 OPERATIONS of the transport case - by inheritance (concern C2).

Three tabs worked in PARALLEL by three specialists (OPS-003 / G14): the server
enforces WHO may write WHICH field (per-tab field guard), never a sequential
station queue. Only the four allowed locks exist (SRS 7-4):
  L1 final freight request needs the POD  (itr.cost.line.action_request_payment)
  L2 execution needs finance access       (itr.payment.execution.create)
  L3 close needs the 10-item checklist    (action_close)
  L4 settled needs two independent flags  (action_settle)
"""
import psycopg2

from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

from .itr_document_type import validate_upload
from .itr_transport_case import TRANSPORT_ENGINE_CTX

TONNAGE_ENGINE_CTX = "itr_tonnage_engine"
REOPEN_CTX = "itr_transport_reopen"

BIJAK_NEEDS = [("unknown", "Not decided"), ("yes", "Bijak required"), ("no", "No bijak needed")]
CLEARANCE_STATES = [("pending", "Pending"), ("in_progress", "In progress"),
                    ("cleared", "Cleared"), ("blocked", "Blocked")]

DOCS_FIELDS = {
    "driver_id", "vehicle_id", "carrier_id", "waybill_issuer", "waybill_number", "waybill_date",
    "waybill_tonnage", "waybill_total_freight", "waybill_currency_id", "insurance_amount",
    "insurance_confirmed", "letter_match_confirmed", "gross_weight", "tare_weight",
    "weighbridge_ticket_no", "weighbridge_file", "weighbridge_file_name", "packing_list_done",
    "packing_file", "packing_file_name", "packing_date", "docs_reviewed_payment",
}
CUSTOMS_FIELDS = {
    "driver_confirmed", "smart_card_checked_on", "needs_bijak", "declaration_file",
    "declaration_file_name", "bijak_file", "bijak_file_name", "customs_broker_id",
    "border_agent_id", "clearance_date", "clearance_hour", "clearance_status",
}
DELIVERY_FIELDS = {
    "docs_final_confirmed", "delivery_receipt", "delivery_receipt_name", "delivered_on", "payee_sheba",
}
FINANCE_FIELDS = {"finance_approved", "finance_settled", "chk_purchase", "chk_sales"}
CREDIT_FIELDS = {"buyer_credit_confirmed"}
SUPERVISOR_FIELDS = {
    "planned_tonnage", "source_item_id", "docs_owner_id", "customs_owner_id", "delivery_owner_id",
    "no_more_dispatch_planned", "manual_effective_tonnage", "manual_effective_reason", "note",
}
TAB_GROUPS = {
    "docs": ("itr_core.group_transport_docs", "itr_core.group_transport_supervisor", "itr_core.group_ceo"),
    "customs": ("itr_core.group_customs_officer", "itr_core.group_transport_supervisor", "itr_core.group_ceo"),
    "delivery": ("itr_core.group_transport_delivery", "itr_core.group_transport_supervisor", "itr_core.group_ceo"),
    "finance": ("itr_core.group_finance_supervisor", "itr_core.group_financial_manager"),
    "credit": ("itr_core.group_receivables_user", "itr_core.group_finance_supervisor", "itr_core.group_ceo"),
    "supervisor": ("itr_core.group_transport_supervisor", "itr_core.group_finance_supervisor", "itr_core.group_ceo"),
}
FIELD_TAB = {}
for tab_name, tab_fields in (("docs", DOCS_FIELDS), ("customs", CUSTOMS_FIELDS), ("delivery", DELIVERY_FIELDS),
                             ("finance", FINANCE_FIELDS), ("credit", CREDIT_FIELDS), ("supervisor", SUPERVISOR_FIELDS)):
    for field_name in tab_fields:
        FIELD_TAB[field_name] = tab_name

CHECKLIST_FIELDS = ("chk_purchase", "chk_sales", "chk_driver", "chk_waybill", "chk_weighbridge",
                    "chk_bijak", "chk_clearance", "chk_delivery", "chk_payments", "finance_approved")


class ItrTransportCase(models.Model):
    _inherit = "itr.transport.case"

    # ---------------------------------------------------- owners (C1 / G15)
    docs_owner_id = fields.Many2one("res.users", string="Fleet & documents specialist", index=True, copy=False)
    customs_owner_id = fields.Many2one("res.users", string="Border & clearance officer", index=True, copy=False)
    delivery_owner_id = fields.Many2one("res.users", string="Delivery & settlement specialist", index=True, copy=False)
    requested_by_id = fields.Many2one(related="trade_case_id.requested_by", string="Ordering CEO", readonly=True)
    buyer_credit_confirmed = fields.Boolean(string="Buyer credit confirmed (OPEN-02)", copy=False)
    buyer_credit_by_id = fields.Many2one("res.users", string="Credit confirmed by", readonly=True, copy=False)

    # ------------------------------------------ tab 1: documents and fleet
    driver_id = fields.Many2one("itr.driver", string="Driver", copy=False)
    driver_mobile = fields.Char(related="driver_id.mobile", string="Driver mobile", readonly=True)
    driver_smart_card_status = fields.Selection(related="driver_id.smart_card_status", readonly=True)
    vehicle_id = fields.Many2one("itr.vehicle", string="Vehicle", copy=False)
    carrier_id = fields.Many2one("res.partner", string="Carrier", domain=[("is_shipping_line", "=", True)])
    waybill_issuer = fields.Char(string="Waybill issuer", help="Carrier / terminal that issued the waybill (OPS-021 scope).")
    waybill_number = fields.Char(string="Waybill number", index=True, copy=False)
    waybill_date = fields.Date(string="Waybill date")
    waybill_tonnage = fields.Float(string="Waybill tonnage", help="OPS-023: never overwrites the effective tonnage.")
    waybill_total_freight = fields.Float(string="Waybill total freight (anchor)")
    waybill_currency_id = fields.Many2one("res.currency", string="Freight currency",
                                          default=lambda self: self.env.company.currency_id)
    waybill_fx_rate = fields.Float(string="Freight conversion rate", readonly=True)
    waybill_freight_base = fields.Float(string="Freight anchor (IRR)", readonly=True,
                                        help="FIN-002: ceiling of the freight cost lines.")
    insurance_amount = fields.Float(string="Cargo insurance amount")
    insurance_confirmed = fields.Boolean(string="Insurance amount confirmed", copy=False)
    insurance_confirmed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Insurance confirmed by")
    insurance_confirmed_on = fields.Datetime(readonly=True, copy=False, string="Insurance confirmed on")
    letter_match_confirmed = fields.Boolean(string="Waybill date / sender / receiver match the release letter", copy=False)
    letter_match_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Letter match confirmed by")
    letter_match_on = fields.Datetime(readonly=True, copy=False, string="Letter match confirmed on")
    gross_weight = fields.Float(string="Gross weight (t)", digits=(16, 3))
    tare_weight = fields.Float(string="Tare weight (t)", digits=(16, 3))
    net_weight = fields.Float(string="Net weight (t)", digits=(16, 3), compute="_compute_net_weight", store=True)
    weighbridge_ticket_no = fields.Char(string="Weighbridge ticket no.")
    weighbridge_file = fields.Binary(string="Weighbridge ticket scan", attachment=True)
    weighbridge_file_name = fields.Char(string="Weighbridge file name")
    weighbridge_recorded_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Weighbridge recorded by")
    weighbridge_recorded_on = fields.Datetime(readonly=True, copy=False, string="Weighbridge recorded on")
    weighbridge_confirmed = fields.Boolean(string="Weighbridge confirmed", readonly=True, copy=False)
    weighbridge_confirmed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Weighbridge confirmed by")
    weighbridge_confirmed_on = fields.Datetime(readonly=True, copy=False, string="Weighbridge confirmed on")
    packing_list_done = fields.Boolean(string="Packing list prepared")
    packing_file = fields.Binary(string="Packing list", attachment=True)
    packing_file_name = fields.Char(string="Packing file name")
    packing_date = fields.Date(string="Packing date")
    docs_reviewed_payment = fields.Boolean(string="Payments operationally reviewed (OPEN-01)")

    # ------------------------------------------ tab 2: border and clearance
    driver_confirmed = fields.Boolean(string="Driver and smart card confirmed", copy=False)
    driver_confirmed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Driver confirmed by")
    smart_card_checked_on = fields.Date(string="Smart card checked on")
    needs_bijak = fields.Selection(BIJAK_NEEDS, string="Bijak needed?", default="unknown", required=True)
    declaration_file = fields.Binary(string="Customs declaration", attachment=True)
    declaration_file_name = fields.Char(string="Declaration file name")
    bijak_file = fields.Binary(string="Bijak", attachment=True)
    bijak_file_name = fields.Char(string="Bijak file name")
    bijak_confirmed = fields.Boolean(string="Bijak step confirmed", readonly=True, copy=False)
    bijak_confirmed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Bijak confirmed by")
    bijak_confirmed_on = fields.Datetime(readonly=True, copy=False, string="Bijak confirmed on")
    customs_broker_id = fields.Many2one("res.partner", string="Customs broker", domain=[("is_customs_agent", "=", True)])
    border_agent_id = fields.Many2one("res.partner", string="Border representative", domain=[("is_border_rep", "=", True)])
    clearance_date = fields.Date(string="Clearance date")
    clearance_hour = fields.Float(string="Clearance time")
    clearance_status = fields.Selection(CLEARANCE_STATES, string="Clearance status", default="pending", required=True)
    clearance_confirmed = fields.Boolean(string="Clearance confirmed", readonly=True, copy=False)
    clearance_confirmed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Clearance confirmed by")
    clearance_confirmed_on = fields.Datetime(readonly=True, copy=False, string="Clearance confirmed on")
    coordination_log_ids = fields.One2many("itr.driver.coordination.log", "transport_case_id", string="Driver coordination log")

    # ------------------------------------------ tab 3: delivery and settlement
    docs_final_confirmed = fields.Boolean(string="Bijak / clearance documents finally confirmed", copy=False)
    docs_final_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Documents finally confirmed by")
    delivery_receipt = fields.Binary(string="Buyer delivery receipt (POD)", attachment=True, copy=False)
    delivery_receipt_name = fields.Char(string="POD file name", copy=False)
    delivery_receipt_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="POD uploaded by")
    delivery_receipt_on = fields.Datetime(readonly=True, copy=False, string="POD uploaded on")
    delivered_on = fields.Date(string="Delivered on")
    payee_sheba = fields.Char(string="Driver / carrier SHEBA")
    payee_sheba_masked = fields.Char(string="SHEBA (masked)", compute="_compute_sheba_masked")
    finance_settled = fields.Boolean(string="Financially settled (finance flag, lock L4)", copy=False)
    cost_line_ids = fields.One2many("itr.cost.line", "transport_case_id", string="Cost lines")
    payment_request_ids = fields.One2many("itr.payment.request", "transport_case_id", string="Payment requests")
    payment_execution_ids = fields.One2many("itr.payment.execution", "transport_case_id", string="Payment executions")
    document_ids = fields.One2many("itr.transport.document", "transport_case_id", string="Documents")

    # ------------------------------------------ tonnage (OPS-023 / BR-005)
    manual_effective_tonnage = fields.Float(string="Documented manual tonnage", digits=(16, 3))
    manual_effective_reason = fields.Char(string="Reason of the manual tonnage")
    effective_tonnage = fields.Float(string="Effective tonnage (t)", digits=(16, 3),
                                     compute="_compute_effective_tonnage", store=True)
    no_more_dispatch_planned = fields.Boolean(string="No further dispatch planned (BR-111)")

    # ------------------------------------------ money roll-ups (read-only, 6.11)
    freight_cost = fields.Float(string="Freight cost (IRR)", compute="_compute_money", store=True)
    customs_cost = fields.Float(string="Customs duty (IRR)", compute="_compute_money", store=True)
    clearance_cost = fields.Float(string="Clearance fee (IRR)", compute="_compute_money", store=True)
    insurance_cost = fields.Float(string="Insurance (IRR)", compute="_compute_money", store=True)
    origin_cost = fields.Float(string="Origin costs (IRR)", compute="_compute_money", store=True)
    other_cost = fields.Float(string="Other costs (IRR)", compute="_compute_money", store=True)
    total_cost = fields.Float(string="Total operational cost (IRR)", compute="_compute_money", store=True)
    total_settled = fields.Float(string="Total settled (IRR)", compute="_compute_money", store=True)
    freight_settled_base = fields.Float(string="Freight settled (IRR)", compute="_compute_money", store=True)
    advance_paid_base = fields.Float(string="Advance paid (IRR)", compute="_compute_money", store=True)
    final_freight_due = fields.Float(string="Final freight due (IRR, FIN-021)", compute="_compute_money", store=True)
    other_cost_description = fields.Char(string="Other cost description (FIN-001)")

    # ------------------------------------------ closing checklist (SRS 10-1)
    chk_purchase = fields.Boolean(string="Purchase documents checked", copy=False)
    chk_sales = fields.Boolean(string="Sales documents checked", copy=False)
    chk_driver = fields.Boolean(string="Driver confirmed", readonly=True, copy=False)
    chk_waybill = fields.Boolean(string="Waybill recorded", readonly=True, copy=False)
    chk_weighbridge = fields.Boolean(string="Weighbridge confirmed", readonly=True, copy=False)
    chk_bijak = fields.Boolean(string="Bijak settled (only if required)", readonly=True, copy=False)
    chk_clearance = fields.Boolean(string="Clearance confirmed", readonly=True, copy=False)
    chk_delivery = fields.Boolean(string="Delivery receipt uploaded", readonly=True, copy=False)
    chk_payments = fields.Boolean(string="Payments settled (BR-101)", compute="_compute_chk_payments", store=True)
    finance_approved = fields.Boolean(string="Finance approved (finance access)", copy=False)
    checklist_progress = fields.Integer(string="Checklist progress (%)", compute="_compute_checklist_progress")
    manual_close_reason = fields.Text(string="Manual close reason", readonly=True, copy=False)
    closed_by_id = fields.Many2one("res.users", readonly=True, copy=False, string="Closed by")
    closed_on = fields.Datetime(readonly=True, copy=False, string="Closed on")
    reopen_reason = fields.Text(string="Reopen reason", readonly=True, copy=False)
    reopen_count = fields.Integer(string="Reopened", readonly=True, copy=False, default=0)

    # ------------------------------------------ duplicate awareness (OPS-026)
    duplicate_driver_count = fields.Integer(compute="_compute_duplicates", string="Other loadings of this driver")
    duplicate_vehicle_count = fields.Integer(compute="_compute_duplicates", string="Other loadings of this plate")

    # ======================================================= computes
    @api.depends("gross_weight", "tare_weight")
    def _compute_net_weight(self):
        for record in self:
            record.net_weight = (record.gross_weight or 0.0) - (record.tare_weight or 0.0)

    @api.constrains("gross_weight", "tare_weight")
    def _check_weights(self):
        for record in self:
            if record.gross_weight or record.tare_weight:
                if record.tare_weight < 0 or record.gross_weight < 0:
                    raise ValidationError(_("Weights cannot be negative (OPS-022)."))
                if record.gross_weight and record.tare_weight and record.gross_weight <= record.tare_weight:
                    raise ValidationError(
                        _("The gross weight (%(g)s t) must be greater than the tare weight (%(t)s t); "
                          "a negative or zero net weight is refused (OPS-022).",
                          g=record.gross_weight, t=record.tare_weight))

    @api.depends("weighbridge_confirmed", "net_weight", "manual_effective_tonnage", "manual_effective_reason")
    def _compute_effective_tonnage(self):
        """OPS-023: confirmed weighbridge > documented manual value > never the plan."""
        for record in self:
            if record.weighbridge_confirmed and record.net_weight > 0:
                record.effective_tonnage = record.net_weight
            elif record.manual_effective_tonnage > 0 and (record.manual_effective_reason or "").strip():
                record.effective_tonnage = record.manual_effective_tonnage
            else:
                record.effective_tonnage = 0.0

    @api.depends("payee_sheba")
    def _compute_sheba_masked(self):
        service = self.env["itr.validation.service"]
        for record in self:
            record.payee_sheba_masked = service.mask_sheba(record.payee_sheba) if record.payee_sheba else ""

    @api.depends("cost_line_ids.base_amount", "cost_line_ids.payment_status", "cost_line_ids.category",
                 "payment_execution_ids.base_amount", "payment_execution_ids.state", "waybill_freight_base")
    def _compute_money(self):
        engine = self.env["itr.money.engine"]
        for record in self:
            figures = engine.transport_totals(record)
            record.freight_cost = figures["freight_cost"]
            record.customs_cost = figures["customs_cost"]
            record.clearance_cost = figures["clearance_cost"]
            record.insurance_cost = figures["insurance_cost"]
            record.origin_cost = figures["origin_cost"]
            record.other_cost = figures["other_cost"]
            record.total_cost = figures["total_cost"]
            record.total_settled = figures["total_settled"]
            record.freight_settled_base = figures["freight_settled"]
            record.advance_paid_base = figures["advance_paid"]
            record.final_freight_due = figures["final_freight_due"]

    @api.constrains("other_cost", "other_cost_description")
    def _check_other_cost_description(self):
        for record in self:
            if record.other_cost > 0 and not (record.other_cost_description or "").strip():
                raise ValidationError(_("A description is mandatory when 'other costs' are greater than zero (FIN-001)."))

    @api.depends("cost_line_ids.amount", "cost_line_ids.currency_id", "cost_line_ids.payment_status",
                 "payment_execution_ids.amount", "payment_execution_ids.currency_id",
                 "payment_execution_ids.state", "waybill_freight_base", "freight_settled_base")
    def _compute_chk_payments(self):
        """BR-101: commitment versus real allocation, PER CURRENCY - never 'one positive payment'."""
        for record in self:
            committed = {}
            for line in record.cost_line_ids.filtered(lambda l: l.payment_status != "rejected"):
                committed[line.currency_id.id] = committed.get(line.currency_id.id, 0.0) + line.amount
            paid = {}
            for execution in record.payment_execution_ids.filtered(lambda e: e.state == "done"):
                paid[execution.currency_id.id] = paid.get(execution.currency_id.id, 0.0) + execution.amount
            ok = all(paid.get(currency, 0.0) + 1e-6 >= amount for currency, amount in committed.items())
            if record.waybill_freight_base > 0 and record.freight_settled_base + 0.5 < record.waybill_freight_base:
                ok = False  # FIN-021: the final freight is still due
            record.chk_payments = ok and (bool(committed) or record.waybill_freight_base <= 0)

    @api.depends(*CHECKLIST_FIELDS, "needs_bijak")
    def _compute_checklist_progress(self):
        for record in self:
            done = sum(1 for name in CHECKLIST_FIELDS if record[name])
            record.checklist_progress = int(done * 100 / len(CHECKLIST_FIELDS))

    @api.depends("driver_id", "vehicle_id")
    def _compute_duplicates(self):
        for record in self:
            record.duplicate_driver_count = self.search_count(
                [("driver_id", "=", record.driver_id.id), ("id", "!=", record.id)]) if record.driver_id else 0
            record.duplicate_vehicle_count = self.search_count(
                [("vehicle_id", "=", record.vehicle_id.id), ("id", "!=", record.id)]) if record.vehicle_id else 0

    # ======================================================= OPS-021 waybill uniqueness
    def init(self):
        super().init()
        self.env.cr.execute("SELECT 1 FROM pg_indexes WHERE indexname = %s", ("itr_transport_case_waybill_uniq",))
        if not self.env.cr.fetchone():
            self.env.cr.execute(
                'CREATE UNIQUE INDEX "itr_transport_case_waybill_uniq" ON "%s" '
                "(company_id, COALESCE(waybill_issuer, ''), waybill_number) "
                "WHERE waybill_number IS NOT NULL AND state != 'cancelled'" % self._table)

    @api.constrains("waybill_number", "waybill_issuer", "company_id", "state")
    def _check_waybill_unique(self):
        # [FIX-P6-1] Flush the pending values INSIDE a savepoint first, so the REAL
        # unique index (OPS-021) always answers as a ValidationError - never as a raw
        # psycopg2.UniqueViolation that aborts the whole transaction (root cause of
        # the red G6-09/G6-10: test_20 ERROR and the verify_phase6 crash after V6-01).
        for record in self:
            if not record.waybill_number or record.state == "cancelled":
                continue
            duplicate_hint = False
            try:
                with self.env.cr.savepoint():
                    record.flush_model(["company_id", "waybill_issuer", "waybill_number", "state"])
            except psycopg2.IntegrityError:
                duplicate_hint = True
            self.env.cr.execute(
                'SELECT name FROM "%s" ' % self._table
                + "WHERE id != %s AND company_id = %s "
                  "AND COALESCE(waybill_issuer, '') = %s AND waybill_number = %s "
                  "AND state != 'cancelled' LIMIT 1",
                (record.id or 0, record.company_id.id, record.waybill_issuer or "", record.waybill_number))
            row = self.env.cr.fetchone()
            if row or duplicate_hint:
                raise ValidationError(
                    _("Waybill %(w)s of issuer '%(i)s' already exists on loading %(n)s (OPS-021). "
                      "Open that loading to see its history.", w=record.waybill_number,
                      i=record.waybill_issuer or "-", n=row[0] if row else "-"))

    @api.constrains("payee_sheba")
    def _check_payee_sheba(self):
        service = self.env["itr.validation.service"]
        for record in self:
            if record.payee_sheba:
                service.check_sheba(record.payee_sheba, res_model=self._name, res_id=record.id)

    # ======================================================= transition table (extends phase 5)
    def _transition_table(self):
        table = super()._transition_table()
        table.update({
            "pending_review": {"loading_authorized", "cancelled"},
            "loading_authorized": {"loaded", "cancelled"},
            "loaded": {"in_transit", "waiting_weighbridge", "cancelled"},
            "in_transit": {"waiting_weighbridge", "waiting_bijak", "waiting_clearance",
                           "waiting_payment", "delivered", "cancelled"},
            "waiting_weighbridge": {"waiting_bijak", "waiting_clearance", "waiting_payment", "delivered", "cancelled"},
            "waiting_bijak": {"waiting_clearance", "waiting_payment", "delivered", "cancelled"},
            "waiting_clearance": {"waiting_payment", "delivered", "cancelled"},
            "waiting_payment": {"delivered", "settled", "closed", "cancelled"},
            "delivered": {"waiting_payment", "settled", "closed", "cancelled"},
            "settled": {"closed"},
            "closed": {"delivered"},   # only through action_reopen (BR-123)
            "cancelled": set(),
        })
        return table

    def _do_transition(self, new_state):
        for record in self:
            if record.state == "closed" and not self.env.context.get(REOPEN_CTX):
                raise UserError(_("A closed loading only moves through the reopen action (BR-123)."))
        return super()._do_transition(new_state)

    # ======================================================= per-tab write guard (6.2 / G14)
    def _engine_write(self, vals):
        return self.with_context(**{TRANSPORT_ENGINE_CTX: True}).write(vals)

    def _check_tab_permissions(self, vals):
        user = self.env.user
        for field_name in vals:
            tab = FIELD_TAB.get(field_name)
            if not tab:
                continue
            if tab == "finance" and self.env.su:
                raise UserError(_("Finance flags are never set as superuser (G01)."))
            if self.env.su and tab != "finance":
                continue
            if not any(user.has_group(g) for g in TAB_GROUPS[tab]):
                raise UserError(
                    _("Field '%(f)s' belongs to the '%(t)s' tab; your role may not edit it "
                      "(SRS 4-3 / G14 / OPS-003).", f=field_name, t=tab))

    def write(self, vals):
        engine = self.env.context.get(TRANSPORT_ENGINE_CTX) or self.env.context.get("itr_cartable_engine")
        if not engine:
            self._check_tab_permissions(vals)
            for record in self:
                if record.state in ("closed", "cancelled") and set(vals) & set(FIELD_TAB):
                    raise UserError(_("Loading %(n)s is %(s)s; its operational data is frozen (OPS-027).",
                                      n=record.name, s=record.state))
            if "delivery_receipt" in vals and vals["delivery_receipt"]:
                for record in self:
                    validate_upload(self.env, vals.get("delivery_receipt_name", record.delivery_receipt_name),
                                    vals["delivery_receipt"], _("Delivery receipt"))
        result = super().write(vals)
        if not engine:
            self._after_write_hooks(vals)
        return result

    def _after_write_hooks(self, vals):
        now = fields.Datetime.now()
        uid = self.env.user.id
        sla = self.env["itr.sla.service"]
        for record in self:
            updates = {}
            if vals.get("driver_id"):
                record._itr_notify("shipment.driver_assigned", {"driver": record.driver_id.name})
                sla.close_watch("transport.driver", record, reason=_("Driver assigned"))
            if vals.get("waybill_number"):
                updates["chk_waybill"] = True
                record._itr_notify("shipment.waybill_recorded", {"waybill": record.waybill_number})
                sla.close_watch("transport.waybill", record, reason=_("Waybill recorded"))
            if "waybill_total_freight" in vals or "waybill_currency_id" in vals:
                if record.waybill_total_freight > 0 and record.waybill_currency_id:
                    fx = self.env["itr.fx.service"].apply_fx(record.waybill_total_freight, record.waybill_currency_id)
                    updates.update({"waybill_fx_rate": fx["conversion_rate"], "waybill_freight_base": fx["base_amount"]})
                else:
                    updates.update({"waybill_fx_rate": 0.0, "waybill_freight_base": 0.0})
            if vals.get("insurance_confirmed"):
                updates.update({"insurance_confirmed_by_id": uid, "insurance_confirmed_on": now})
            if vals.get("letter_match_confirmed"):
                updates.update({"letter_match_by_id": uid, "letter_match_on": now})
            if vals.get("driver_confirmed"):
                updates.update({"driver_confirmed_by_id": uid, "chk_driver": True})
            if "driver_confirmed" in vals and not vals["driver_confirmed"]:
                updates["chk_driver"] = False
            if vals.get("docs_final_confirmed"):
                updates["docs_final_by_id"] = uid
            if vals.get("buyer_credit_confirmed"):
                updates["buyer_credit_by_id"] = uid
            if vals.get("delivery_receipt"):
                updates.update({"delivery_receipt_by_id": uid, "delivery_receipt_on": now, "chk_delivery": True})
                record._itr_notify("shipment.pod_uploaded")
                sla.close_watch("transport.pod", record, reason=_("Delivery receipt uploaded"))
            if "manual_effective_tonnage" in vals or "manual_effective_reason" in vals:
                record._rollup_effective_tonnage()
            if updates:
                record._engine_write(updates)
            if vals.get("delivery_receipt") and "delivered" in record._transition_table().get(record.state, set()):
                record._do_transition("delivered")

    # ======================================================= tonnage roll-up (OPS-023 / BR-005)
    def _rollup_effective_tonnage(self):
        """Item effective tonnage = sum of the confirmed loadings of that item.

        A measured figure, not a business decision: written through the tonnage
        engine context of phase 5 with a system cursor (the confirming officer
        has no ACL on the commercial goods row on purpose).
        """
        for item in self.mapped("source_item_id"):
            loadings = self.sudo().search([("source_item_id", "=", item.id), ("state", "!=", "cancelled")])  # ITR-SUDO-OK system roll-up
            total = sum(loadings.mapped("effective_tonnage"))
            item.sudo().with_context(**{TONNAGE_ENGINE_CTX: True}).write({"effective_tonnage": total})  # ITR-SUDO-OK system roll-up
        return True

    # ======================================================= actions - supervisor
    def action_authorize_loading(self):
        """pending_review -> loading_authorized; assigns the three tab owners (G15)."""
        self._require_group("itr_core.group_transport_supervisor", "authorize loading")
        credit_required = self.env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
            "itr_transport.require_credit_check_before_loading", "1") == "1"
        sla = self.env["itr.sla.service"]
        for record in self:
            if record.state != "pending_review":
                raise UserError(_("Only a loading pending review can be authorised."))
            if credit_required and not record.buyer_credit_confirmed:
                raise UserError(
                    _("Policy OPEN-02 is active: the buyer credit check must be confirmed before the "
                      "loading authorisation of %(n)s.", n=record.name))
            owners = {}
            for field_name, group in (("docs_owner_id", "itr_core.group_transport_docs"),
                                      ("customs_owner_id", "itr_core.group_customs_officer"),
                                      ("delivery_owner_id", "itr_core.group_transport_delivery")):
                if not record[field_name]:
                    user = record._least_loaded_of_group(group, field_name)
                    if user:
                        owners[field_name] = user.id
            if owners:
                record._engine_write(owners)
            record._do_transition("loading_authorized")
            record._itr_notify("transport.loading_authorized")
            sla.open_watch("transport.driver", record, record.docs_owner_id)
            sla.open_watch("transport.waybill", record, record.docs_owner_id)
            record.message_post(body=_("Loading authorised; tab owners: %(d)s / %(c)s / %(v)s",
                                       d=record.docs_owner_id.name or "-", c=record.customs_owner_id.name or "-",
                                       v=record.delivery_owner_id.name or "-"))
        return True

    def _least_loaded_of_group(self, group_xmlid, owner_field):
        group = self.env.ref(group_xmlid, raise_if_not_found=False)
        if not group:
            return False
        blocked = self._cartable_blocked_user_ids()
        users = group.users if "users" in group._fields else group.user_ids
        candidates = [u for u in users if u.active and u.id not in blocked]
        if not candidates:
            return False
        loads = {u.id: self.search_count([(owner_field, "=", u.id), ("state", "not in", ("closed", "cancelled"))])
                 for u in candidates}
        return min(candidates, key=lambda u: (loads[u.id], u.id))

    def assign_tab(self, tab, user, reason=None):
        """Supervisor reassignment of one tab, with a mandatory reason, inside the team (SEC-004)."""
        self.ensure_one()
        field_name = {"docs": "docs_owner_id", "customs": "customs_owner_id", "delivery": "delivery_owner_id"}.get(tab)
        if not field_name:
            raise UserError(_("Unknown tab: %(t)s", t=tab))
        if not (reason or "").strip():
            raise UserError(_("A reassignment always requires a mandatory reason."))
        actor = self.env.user
        unrestricted = actor.has_group("itr_core.group_ceo") or actor.has_group("itr_core.group_financial_manager")
        if not unrestricted:
            self._require_group("itr_core.group_transport_supervisor", "reassign tab")
            subordinates = self.env["itr.supervisor.team"].get_subordinate_users(actor.id)
            if user not in subordinates:
                raise UserError(_("A supervisor may only assign work to a member of his own team (SEC-004)."))
        if not user.active or user.id in self._cartable_blocked_user_ids():
            raise UserError(_("Administrator, OdooBot or an archived user can never own a work item (SEC-002)."))
        previous = self[field_name]
        self._engine_write({field_name: user.id})
        self.env["itr.work.assignment.log"].create({
            "res_model": self._name, "res_id": self.id, "record_display": "%s [%s]" % (self.display_name, tab),
            "from_user_id": previous.id if previous else False, "to_user_id": user.id,
            "reason": reason, "state_at_assignment": self.state})
        self.activity_schedule("mail.mail_activity_data_todo", user_id=user.id, summary=reason)
        self.message_post(body=_("Tab '%(t)s' reassigned to %(u)s. Reason: %(r)s", t=tab, u=user.display_name, r=reason))
        return True

    # ======================================================= actions - documents tab
    def action_mark_loaded(self):
        self._require_group(("itr_core.group_transport_docs", "itr_core.group_transport_supervisor"), "mark loaded")
        for record in self:
            if record.state != "loading_authorized":
                raise UserError(_("Only an authorised loading can be marked as loaded."))
            missing = [label for ok, label in (
                (record.driver_id, _("driver")), (record.vehicle_id, _("vehicle")),
                (record.waybill_number, _("waybill number")), (record.waybill_total_freight > 0, _("waybill total freight")),
                (record.insurance_confirmed, _("insurance confirmation (X11)")),
                (record.letter_match_confirmed, _("release letter match (X11)"))) if not ok]
            if missing:
                raise UserError(_("Before 'loaded' the documents tab must complete: %(m)s.", m=", ".join(missing)))
            record._do_transition("loaded")
            self.env["itr.sla.service"].open_watch("transport.weighbridge", record, record.docs_owner_id)
        return True

    def action_depart(self):
        self._require_group(("itr_core.group_transport_docs", "itr_core.group_transport_supervisor"), "depart")
        for record in self:
            if record.state != "loaded":
                raise UserError(_("Only a loaded truck can depart."))
            record._do_transition("in_transit")
        return True

    def action_record_weighbridge(self):
        """6.5 - the RECORDING responsible (documents tab)."""
        self._require_group(("itr_core.group_transport_docs", "itr_core.group_transport_supervisor"), "record weighbridge")
        for record in self:
            if not (record.gross_weight and record.tare_weight):
                raise UserError(_("Gross and tare weights are required before recording the weighbridge."))
            record._engine_write({"weighbridge_recorded_by_id": self.env.user.id,
                                  "weighbridge_recorded_on": fields.Datetime.now()})
            if record.state in ("loaded", "in_transit"):
                record._do_transition("waiting_weighbridge")
            record._itr_notify("shipment.weighbridge_recorded", {"net": record.net_weight})
        return True

    # ======================================================= actions - customs tab
    def action_confirm_weighbridge(self):
        """6.5 - the CONFIRMING responsible (border tab) - a different person."""
        self._require_group(("itr_core.group_customs_officer", "itr_core.group_transport_supervisor"), "confirm weighbridge")
        sla = self.env["itr.sla.service"]
        for record in self:
            if not record.weighbridge_recorded_on:
                raise UserError(_("The weighbridge must be recorded by the documents specialist first."))
            if record.weighbridge_recorded_by_id == self.env.user:
                raise UserError(_("Weighbridge recording and confirmation are two different responsibles (checklist 6.5)."))
            if not record.source_item_id:
                raise UserError(_("Set the goods row (source item) of this loading before confirming the weighbridge (OPS-023)."))
            record._engine_write({"weighbridge_confirmed": True, "weighbridge_confirmed_by_id": self.env.user.id,
                                  "weighbridge_confirmed_on": fields.Datetime.now(), "chk_weighbridge": True})
            record._rollup_effective_tonnage()
            sla.close_watch("transport.weighbridge", record, reason=_("Weighbridge confirmed"))
            if record.needs_bijak == "no":
                if "waiting_clearance" in record._transition_table().get(record.state, set()):
                    record._do_transition("waiting_clearance")
                record._engine_write({"chk_bijak": True, "bijak_confirmed": True})
            else:
                if "waiting_bijak" in record._transition_table().get(record.state, set()):
                    record._do_transition("waiting_bijak")
                sla.open_watch("transport.bijak", record, record.customs_owner_id)
        return True

    def action_confirm_bijak(self):
        """6.6 / OPS-024: 'bijak needed' => declaration AND bijak files mandatory."""
        self._require_group(("itr_core.group_customs_officer", "itr_core.group_transport_supervisor"), "confirm bijak")
        sla = self.env["itr.sla.service"]
        for record in self:
            if record.needs_bijak == "unknown":
                raise UserError(_("Decide first whether a bijak is needed (OPS-024)."))
            if not record.waybill_number or not record.weighbridge_confirmed:
                raise UserError(_("The bijak step depends on the waybill and the confirmed weighbridge (real documentary dependency)."))
            if record.needs_bijak == "yes" and not (record.declaration_file and record.bijak_file):
                raise UserError(_("A bijak is required: upload BOTH the customs declaration and the bijak before confirming (OPS-024)."))
            record._engine_write({"bijak_confirmed": True, "bijak_confirmed_by_id": self.env.user.id,
                                  "bijak_confirmed_on": fields.Datetime.now(), "chk_bijak": True})
            if record.needs_bijak == "yes":
                record._itr_notify("shipment.bijak_uploaded")
            sla.close_watch("transport.bijak", record, reason=_("Bijak step confirmed"))
            if "waiting_clearance" in record._transition_table().get(record.state, set()):
                record._do_transition("waiting_clearance")
            sla.open_watch("transport.clearance", record, record.customs_owner_id)
        return True

    def action_confirm_clearance(self):
        """Operational gate of the clearance - independent from the customs PAYMENT (SRS 7-3)."""
        self._require_group(("itr_core.group_customs_officer", "itr_core.group_transport_supervisor"), "confirm clearance")
        sla = self.env["itr.sla.service"]
        for record in self:
            if not record.bijak_confirmed:
                raise UserError(_("The bijak step must be settled before the clearance is confirmed."))
            if record.clearance_status != "cleared":
                raise UserError(_("Set the clearance status to 'cleared' first."))
            if not (record.customs_broker_id or record.border_agent_id):
                raise UserError(_("Record the customs broker or the border representative (SRS 7-2)."))
            record._engine_write({"clearance_confirmed": True, "clearance_confirmed_by_id": self.env.user.id,
                                  "clearance_confirmed_on": fields.Datetime.now(), "chk_clearance": True,
                                  "clearance_date": record.clearance_date or fields.Date.context_today(record)})
            record._itr_notify("shipment.clearance_recorded")
            sla.close_watch("transport.clearance", record, reason=_("Clearance confirmed"))
            if "waiting_payment" in record._transition_table().get(record.state, set()):
                record._do_transition("waiting_payment")
            sla.open_watch("transport.pod", record, record.delivery_owner_id)
        return True

    def action_log_coordination(self, kind="call", note=None):
        self.ensure_one()
        note = (note or self.env.context.get("itr_note") or "").strip() or _("Coordination with the driver")
        return self.env["itr.driver.coordination.log"].create({
            "transport_case_id": self.id, "kind": kind, "note": note})

    # ======================================================= actions - settlement / closing
    def action_settle(self):
        """Lock L4 (policy-driven): two INDEPENDENT flags, never a serial chain."""
        self._require_group(("itr_core.group_transport_delivery", "itr_core.group_transport_supervisor",
                             "itr_core.group_finance_supervisor"), "settle")
        for record in self:
            if not record.docs_final_confirmed:
                raise UserError(_("The delivery tab must confirm the final bijak / clearance documents first (lock L4, flag 1)."))
            if not record.finance_settled:
                raise UserError(_("The finance unit must flag the loading as financially settled (lock L4, flag 2)."))
            record._do_transition("settled")
        return True

    def _checklist_missing(self):
        self.ensure_one()
        missing = []
        for name in CHECKLIST_FIELDS:
            if name == "chk_bijak" and self.needs_bijak == "no" and self.bijak_confirmed:
                continue
            if not self[name]:
                missing.append(name)
        return missing

    def _finish_close(self, manual_reason=None):
        self.ensure_one()
        self._engine_write({"closed_by_id": self.env.user.id, "closed_on": fields.Datetime.now(),
                            "manual_close_reason": manual_reason or False, "current_owner_id": False})
        self._do_transition("closed")
        self._rollup_effective_tonnage()
        if manual_reason:
            self._itr_notify("case.closed_manually", {"reason": manual_reason})
            self._maybe_record_shortfall()
        self.trade_case_id._notify_ready_to_close_if_done()
        return True

    def action_close(self):
        """Lock L3: no 'closed' before all ten checklist items are green (BR-102)."""
        self._require_group(("itr_core.group_finance_supervisor", "itr_core.group_transport_supervisor"), "close")
        for record in self:
            if record.state not in ("waiting_payment", "delivered", "settled"):
                raise UserError(_("Loading %(n)s cannot be closed from state %(s)s.", n=record.name, s=record.state))
            missing = record._checklist_missing()
            if missing:
                raise UserError(
                    _("Closing is blocked: %(k)s of 10 checklist items are missing on %(n)s: %(m)s (BR-102).",
                      k=len(missing), n=record.name, m=", ".join(missing)))
            record._finish_close()
        return True

    def action_manual_close(self, reason=None):
        """BR-112: manual close with a mandatory free-text reason (shortage / discrepancy)."""
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        self._require_group(("itr_core.group_finance_supervisor", "itr_core.group_transport_supervisor"), "manual close")
        if not reason:
            raise UserError(_("A manual close requires a mandatory free-text reason (BR-112)."))
        for record in self:
            if record.state not in ("waiting_payment", "delivered", "settled"):
                raise UserError(_("Loading %(n)s cannot be closed from state %(s)s.", n=record.name, s=record.state))
            if not record.finance_approved:
                raise UserError(_("Even a manual close needs the finance approval flag (lock L3 / finance access)."))
            record._finish_close(manual_reason=reason)
        return True

    def action_reopen(self, reason=None):
        """BR-123: reopen a closed loading - special group + reason + history + notification."""
        reason = (reason or self.env.context.get("itr_reason") or "").strip()
        if self.env.su:
            raise UserError(_("Business transitions are never executed as superuser (G01/Q03)."))
        user = self.env.user
        if not (user.has_group("itr_core.group_financial_manager") or user.has_group("itr_base.group_itr_validation_override")):
            raise UserError(_("Only the financial manager or the validation-override group may reopen a closed loading (BR-123)."))
        if not reason:
            raise UserError(_("Reopening requires a mandatory reason (BR-123)."))
        for record in self:
            if record.state != "closed":
                raise UserError(_("Only a closed loading can be reopened."))
            record._engine_write({"reopen_reason": reason, "reopen_count": record.reopen_count + 1,
                                  "finance_approved": False})
            record.with_context(**{REOPEN_CTX: True})._do_transition("delivered")
            record._hand_over_to_group("itr_core.group_finance_supervisor", _("Loading reopened: %(r)s", r=reason))
            record.message_post(body=_("Loading reopened (version %(v)s). Reason: %(r)s", v=record.reopen_count, r=reason))
        return True

    def action_cancel(self, reason=None):
        result = super().action_cancel(reason)
        self._rollup_effective_tonnage()
        return result

    # ======================================================= shortfall (6.16 / BR-111 / BR-121)
    def _maybe_record_shortfall(self):
        self.ensure_one()
        item = self.source_item_id
        if not item or not self.no_more_dispatch_planned:
            return False
        siblings = self.sudo().search([("source_item_id", "=", item.id), ("state", "!=", "cancelled")])  # ITR-SUDO-OK system read
        if any(s.state not in ("closed", "settled", "delivered") for s in siblings):
            return False
        if any(not s.delivery_receipt for s in siblings):
            return False  # BR-111: every delivery receipt registered
        effective = sum(siblings.mapped("effective_tonnage"))
        remaining = (item.contract_tonnage or 0.0) - effective
        if remaining <= 1e-6:
            return False
        rate = item.purchase_fx_rate or 1.0
        amount_base = remaining * (item.purchase_price_unit or 0.0) * rate
        Shortfall = self.env["itr.factory.shortfall"]
        existing = Shortfall.search([("trade_case_item_id", "=", item.id)], limit=1)
        vals = {"shortfall_tonnage": remaining, "shortfall_amount_base": amount_base,
                "goods_description": item.name,
                "notes": _("Recorded automatically at the manual close of %(n)s.", n=self.name)}
        if existing:
            if existing.state == "open":
                existing.write(vals)
            shortfall = existing
        else:
            vals.update({"supplier_id": item.case_id.factory_id.id, "trade_case_id": item.case_id.id,
                         "trade_case_item_id": item.id})
            if not vals["supplier_id"]:
                raise UserError(_("The trade case has no factory; the shortfall cannot be recorded (BR-111)."))
            shortfall = Shortfall.create(vals)
        shortfall.message_post(body=_("Shortfall %(t)s t recorded from loading %(n)s.", t=remaining, n=self.name))
        self.env["itr.notification.service"].notify(
            "factory_debt.recorded", shortfall._name, shortfall.id,
            {"tonnage": remaining, "occurrence_id": "shortfall-%s-%s" % (shortfall.id, self.id)})
        return shortfall

    def action_open_driver_history(self):
        self.ensure_one()
        return {"type": "ir.actions.act_window", "name": _("Loadings of this driver"),
                "res_model": "itr.transport.case", "view_mode": "list,form",
                "domain": [("driver_id", "=", self.driver_id.id)], "context": {"active_test": False}}
PYEOF

# ----------------------------------- models/itr_factory_shortfall_ops.py --
write_utf8 "${TRN_DIR}/models/itr_factory_shortfall_ops.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Partial, quantity-based settlements of the factory shortfall (BR-122) by
inheritance of the phase-4 skeleton (never rewritten)."""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError


class ItrFactoryShortfall(models.Model):
    _inherit = "itr.factory.shortfall"

    settlement_ids = fields.One2many("itr.factory.shortfall.settlement", "shortfall_id", string="Settlements")
    settled_tonnage = fields.Float(string="Settled tonnage", compute="_compute_settled", store=True)
    settled_amount_base = fields.Float(string="Settled amount (IRR)", compute="_compute_settled", store=True)
    remaining_tonnage = fields.Float(string="Remaining tonnage", compute="_compute_settled", store=True)
    age_days = fields.Integer(string="Age (days)", compute="_compute_age")

    @api.depends("settlement_ids.settled_tonnage", "settlement_ids.settled_amount_base", "shortfall_tonnage")
    def _compute_settled(self):
        for record in self:
            record.settled_tonnage = sum(record.settlement_ids.mapped("settled_tonnage"))
            record.settled_amount_base = sum(record.settlement_ids.mapped("settled_amount_base"))
            record.remaining_tonnage = max(0.0, (record.shortfall_tonnage or 0.0) - record.settled_tonnage)

    def _compute_age(self):
        today = fields.Date.context_today(self)
        for record in self:
            created = record.create_date.date() if record.create_date else today
            record.age_days = (today - created).days

    def _recompute_state(self):
        for record in self:
            if record.settled_tonnage <= 1e-6:
                state = "open"
            elif record.settled_tonnage + 1e-6 >= record.shortfall_tonnage:
                state = "settled"
            else:
                state = "partially_settled"
            if state != record.state:
                record.write({"state": state})
                if state == "settled":
                    self.env["itr.notification.service"].notify(
                        "factory_debt.settled", record._name, record.id,
                        {"occurrence_id": "shortfall-settled-%s" % record.id})
        return True

    def unlink(self):
        raise UserError(_("A factory shortfall row is never deleted; settle it (BR-122)."))


class ItrFactoryShortfallSettlement(models.Model):
    _name = "itr.factory.shortfall.settlement"
    _description = "Factory Shortfall Settlement"
    _order = "id desc"

    shortfall_id = fields.Many2one("itr.factory.shortfall", string="Shortfall", required=True,
                                   ondelete="restrict", index=True)
    settled_tonnage = fields.Float(string="Settled tonnage", required=True)
    settled_amount_base = fields.Float(string="Settled amount (IRR)")
    settlement_date = fields.Date(string="Settlement date", required=True, default=fields.Date.context_today)
    settled_by_id = fields.Many2one("res.users", string="Settled by", readonly=True,
                                    default=lambda self: self.env.user)
    compensation_case_id = fields.Many2one("itr.trade.case", string="Compensating trade case",
                                           help="BR-122: the deal that compensated the shortage.")
    note = fields.Char(string="Note")

    @api.constrains("settled_tonnage", "shortfall_id")
    def _check_tonnage(self):
        for record in self:
            if record.settled_tonnage <= 0:
                raise ValidationError(_("The settled tonnage must be greater than zero."))
            total = sum(record.shortfall_id.settlement_ids.mapped("settled_tonnage"))
            if total > record.shortfall_id.shortfall_tonnage + 1e-6:
                raise ValidationError(_("The settlements exceed the shortfall tonnage."))

    @api.model_create_multi
    def create(self, vals_list):
        if self.env.su:
            raise UserError(_("Settlements are never recorded as superuser (G01/Q03)."))
        records = super().create(vals_list)
        records.mapped("shortfall_id")._recompute_state()
        return records

    def write(self, vals):
        raise UserError(_("A settlement is append-only; record a correcting settlement instead."))

    def unlink(self):
        raise UserError(_("A settlement is append-only and cannot be deleted."))
PYEOF

# --------------------------------------- models/itr_trade_case_transport.py --
write_utf8 "${TRN_DIR}/models/itr_trade_case_transport.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase-6 extension of the trade case by inheritance: loadings roll-up,
operational cost / settlement from the single money engine and the final
financial close (slips_issued -> closed) by the finance supervisor."""
from odoo import _, api, fields, models
from odoo.exceptions import UserError


class ItrTradeCase(models.Model):
    _inherit = "itr.trade.case"

    transport_case_ids = fields.One2many("itr.transport.case", "trade_case_id", string="Loadings")
    transport_case_count = fields.Integer(string="Loadings", compute="_compute_loading_stats")
    loadings_all_closed = fields.Boolean(string="All loadings closed", compute="_compute_loading_stats")
    effective_tonnage_total = fields.Float(string="Total effective tonnage", compute="_compute_loading_stats")
    operational_cost_base = fields.Float(string="Operational cost (IRR)", compute="_compute_totals", store=True)
    total_settled_base = fields.Float(string="Total settled (IRR)", compute="_compute_totals", store=True)

    @api.depends("transport_case_ids.state", "transport_case_ids.effective_tonnage")
    def _compute_loading_stats(self):
        for case in self:
            active = case.transport_case_ids.filtered(lambda t: t.state != "cancelled")
            case.transport_case_count = len(active)
            case.loadings_all_closed = bool(active) and all(t.state == "closed" for t in active)
            case.effective_tonnage_total = sum(active.mapped("effective_tonnage"))

    @api.depends("transport_case_ids.total_cost", "transport_case_ids.total_settled", "transport_case_ids.state")
    def _compute_totals(self):
        super()._compute_totals()
        engine = self.env["itr.money.engine"]
        for case in self:
            totals = engine.case_totals(case)
            case.operational_cost_base = totals.get("operational_cost", 0.0)
            case.total_settled_base = totals.get("total_settled", 0.0)
            case.estimated_profit_base = totals["estimated_profit"]

    def _notify_ready_to_close_if_done(self):
        for case in self:
            if case.state == "slips_issued" and case.loadings_all_closed:
                self.env["itr.notification.service"].notify(
                    "trade_case.ready_to_close", case._name, case.id,
                    {"occurrence_id": "ready-%s-%s" % (case.id, case.transport_case_count)})
        return True

    def action_close_case(self):
        """slips_issued -> closed (the phase-4 table already allows it)."""
        for case in self:
            if self.env.su:
                raise UserError(_("Business transitions are never executed as superuser (G01/Q03)."))
            if not self.env.user.has_group("itr_core.group_finance_supervisor"):
                raise UserError(_("Only the finance supervisor closes a trade case financially (SRS section 4)."))
            if case.state != "slips_issued":
                raise UserError(_("Only a case with issued sales slips can be closed."))
            open_slips = case.sales_slip_ids.filtered(lambda s: s.state in ("draft", "issued"))
            if open_slips:
                raise UserError(_("Sales slips %(s)s are not handed over to transport yet.",
                                  s=", ".join(open_slips.mapped("name"))))
            if not case.loadings_all_closed:
                raise UserError(_("Every loading of the case must be closed (or cancelled) first."))
            case._do_transition("closed")
            case.with_context(itr_trade_state_engine=True).write({"current_owner_id": False})
        return True

    def action_open_loadings(self):
        self.ensure_one()
        return {"type": "ir.actions.act_window", "name": _("Loadings"), "res_model": "itr.transport.case",
                "view_mode": "kanban,list,form", "domain": [("trade_case_id", "=", self.id)]}
PYEOF

# ------------------------------------------------------------- security ----
write_utf8 "${TRN_DIR}/security/itr_transport_phase6_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">
        <record id="rule_itr_cost_line_company" model="ir.rule">
            <field name="name">Cost line: company rule</field>
            <field name="model_id" ref="itr_transport.model_itr_cost_line"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
        <record id="rule_itr_payment_request_company" model="ir.rule">
            <field name="name">Payment request: company rule</field>
            <field name="model_id" ref="itr_transport.model_itr_payment_request"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
        <record id="rule_itr_payment_execution_company" model="ir.rule">
            <field name="name">Payment execution: company rule</field>
            <field name="model_id" ref="itr_transport.model_itr_payment_execution"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>
        <!-- SEC-014 basis: financial documents hidden from operational groups (phase 7 finalises) -->
        <record id="rule_itr_transport_document_financial" model="ir.rule">
            <field name="name">Transport document: financial rows only for finance / management</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_document"/>
            <field name="domain_force">[('is_financial', '=', False)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_transport_docs')), (4, ref('itr_core.group_customs_officer')), (4, ref('itr_core.group_transport_delivery'))]"/>
        </record>
        <record id="rule_itr_transport_document_all" model="ir.rule">
            <field name="name">Transport document: full access</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_document"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_transport_supervisor')), (4, ref('itr_core.group_finance_supervisor')), (4, ref('itr_core.group_financial_manager')), (4, ref('itr_core.group_ceo')), (4, ref('itr_core.group_auditor'))]"/>
        </record>
    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${TRN_DIR}/data/itr_transport_phase6_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="seq_itr_payment_request" model="ir.sequence">
            <field name="name">Payment Request</field>
            <field name="code">itr.payment.request</field>
            <field name="prefix">PR/%(range_year)s/</field>
            <field name="padding">5</field>
            <field name="company_id" eval="False"/>
        </record>
        <!-- Q07: policies are PARAMETERS, never code (OPEN-01 / OPEN-02 / OPS-025) -->
        <record id="param_payment_docs_review_required" model="ir.config_parameter">
            <field name="key">itr_transport.payment_docs_review_required</field>
            <field name="value">0</field>
        </record>
        <record id="param_require_credit_check_before_loading" model="ir.config_parameter">
            <field name="key">itr_transport.require_credit_check_before_loading</field>
            <field name="value">1</field>
        </record>
        <record id="param_upload_max_mb" model="ir.config_parameter">
            <field name="key">itr_transport.upload_max_mb</field>
            <field name="value">10</field>
        </record>

        <!-- 6.9: the six seed charge types - customs and clearance are two records (G05) -->
        <record id="charge_advance_freight" model="itr.charge.type">
            <field name="name">Advance freight</field>
            <field name="code">advance_freight</field>
            <field name="category">freight</field>
            <field name="sequence">10</field>
            <field name="is_advance" eval="True"/>
            <field name="counts_in_freight_anchor" eval="True"/>
            <field name="payee_type">driver</field>
            <field name="is_seed" eval="True"/>
        </record>
        <record id="charge_final_freight" model="itr.charge.type">
            <field name="name">Final freight settlement</field>
            <field name="code">final_freight</field>
            <field name="category">freight</field>
            <field name="sequence">20</field>
            <field name="requires_pod" eval="True"/>
            <field name="counts_in_freight_anchor" eval="True"/>
            <field name="payee_type">driver</field>
            <field name="is_seed" eval="True"/>
        </record>
        <record id="charge_customs_duty" model="itr.charge.type">
            <field name="name">Customs duty</field>
            <field name="code">customs_duty</field>
            <field name="category">customs</field>
            <field name="sequence">30</field>
            <field name="payee_type">customs</field>
            <field name="is_seed" eval="True"/>
        </record>
        <record id="charge_clearance_fee" model="itr.charge.type">
            <field name="name">Clearance fee</field>
            <field name="code">clearance_fee</field>
            <field name="category">clearance</field>
            <field name="sequence">40</field>
            <field name="payee_type">broker</field>
            <field name="is_seed" eval="True"/>
        </record>
        <record id="charge_cargo_insurance" model="itr.charge.type">
            <field name="name">Cargo insurance</field>
            <field name="code">cargo_insurance</field>
            <field name="category">insurance</field>
            <field name="sequence">50</field>
            <field name="payee_type">insurer</field>
            <field name="is_seed" eval="True"/>
        </record>
        <record id="charge_other" model="itr.charge.type">
            <field name="name">Other cost</field>
            <field name="code">other_cost</field>
            <field name="category">other</field>
            <field name="sequence">60</field>
            <field name="payee_type">other</field>
            <field name="is_seed" eval="True"/>
        </record>

        <!-- DM-108: document types (gap of the phased plan) -->
        <record id="doc_signed_document" model="itr.document.type"><field name="name">Signed document</field><field name="code">signed_document</field><field name="sequence">10</field><field name="is_financial" eval="True"/><field name="is_seed" eval="True"/></record>
        <record id="doc_proforma" model="itr.document.type"><field name="name">Proforma</field><field name="code">proforma</field><field name="sequence">20</field><field name="is_seed" eval="True"/></record>
        <record id="doc_waybill" model="itr.document.type"><field name="name">Waybill</field><field name="code">waybill</field><field name="sequence">30</field><field name="is_seed" eval="True"/></record>
        <record id="doc_weighbridge" model="itr.document.type"><field name="name">Weighbridge ticket</field><field name="code">weighbridge</field><field name="sequence">40</field><field name="is_seed" eval="True"/></record>
        <record id="doc_declaration" model="itr.document.type"><field name="name">Customs declaration</field><field name="code">declaration</field><field name="sequence">50</field><field name="is_seed" eval="True"/></record>
        <record id="doc_bijak" model="itr.document.type"><field name="name">Bijak</field><field name="code">bijak</field><field name="sequence">60</field><field name="is_seed" eval="True"/></record>
        <record id="doc_clearance" model="itr.document.type"><field name="name">Clearance document</field><field name="code">clearance</field><field name="sequence">70</field><field name="is_seed" eval="True"/></record>
        <record id="doc_delivery_receipt" model="itr.document.type"><field name="name">Delivery receipt (POD)</field><field name="code">delivery_receipt</field><field name="sequence">80</field><field name="is_seed" eval="True"/></record>
        <record id="doc_payment_receipt" model="itr.document.type"><field name="name">Payment receipt</field><field name="code">payment_receipt</field><field name="sequence">90</field><field name="is_financial" eval="True"/><field name="is_seed" eval="True"/></record>
        <record id="doc_packing_list" model="itr.document.type"><field name="name">Packing list</field><field name="code">packing_list</field><field name="sequence">100</field><field name="is_seed" eval="True"/></record>
        <record id="doc_other" model="itr.document.type"><field name="name">Other</field><field name="code">other</field><field name="sequence">110</field><field name="is_seed" eval="True"/></record>

        <!-- DM-101: the two SRS borders missing from the phase-3 seed (additive, never a rename) -->
        <record id="border_shalamcheh" model="itr.border">
            <field name="name">مرز شلمچه (عراق)</field>
            <field name="code">SHALAMCHEH</field>
            <field name="border_type">land</field>
            <field name="sequence">45</field>
            <field name="has_customs_office" eval="True"/>
        </record>
        <record id="border_parvizkhan" model="itr.border">
            <field name="name">مرز پرویزخان (عراق)</field>
            <field name="code">PARVIZKHAN</field>
            <field name="border_type">land</field>
            <field name="sequence">46</field>
            <field name="has_customs_office" eval="True"/>
        </record>

        <!-- NOT-031 / OPEN-06: SLA policies - defaults editable from the UI, never in code -->
        <record id="sla_transport_driver" model="itr.sla.policy"><field name="policy_key">transport.driver</field><field name="name">Driver registration</field><field name="res_model">itr.transport.case</field><field name="task_key">driver</field><field name="deadline_minutes">120</field></record>
        <record id="sla_transport_waybill" model="itr.sla.policy"><field name="policy_key">transport.waybill</field><field name="name">Waybill registration</field><field name="res_model">itr.transport.case</field><field name="task_key">waybill</field><field name="deadline_minutes">120</field></record>
        <record id="sla_transport_weighbridge" model="itr.sla.policy"><field name="policy_key">transport.weighbridge</field><field name="name">Weighbridge registration</field><field name="res_model">itr.transport.case</field><field name="task_key">weighbridge</field><field name="deadline_minutes">180</field></record>
        <record id="sla_transport_bijak" model="itr.sla.policy"><field name="policy_key">transport.bijak</field><field name="name">Bijak decision</field><field name="res_model">itr.transport.case</field><field name="task_key">bijak</field><field name="deadline_minutes">240</field></record>
        <record id="sla_transport_clearance" model="itr.sla.policy"><field name="policy_key">transport.clearance</field><field name="name">Clearance</field><field name="res_model">itr.transport.case</field><field name="task_key">clearance</field><field name="deadline_minutes">720</field></record>
        <record id="sla_transport_pod" model="itr.sla.policy"><field name="policy_key">transport.pod</field><field name="name">Delivery receipt</field><field name="res_model">itr.transport.case</field><field name="task_key">pod</field><field name="deadline_minutes">1440</field></record>
    </data>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/data/itr_transport_phase6_events.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Only the catalogue events this phase actually fires (ADR-020: phase 10 refers to these xmlids) -->
    <data noupdate="1">
        <record id="event_transport_loading_authorized" model="itr.notification.event">
            <field name="event_key">transport.loading_authorized</field><field name="title">Loading authorised</field><field name="category">transport</field>
            <field name="dynamic_user_field">docs_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_docs'))]"/>
            <field name="internal_subject">Loading {{name}} authorised</field><field name="internal_body">Loading {{name}} ({{sales_ref}}) is authorised; register the driver, the fleet and the waybill.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_driver_assigned" model="itr.notification.event">
            <field name="event_key">shipment.driver_assigned</field><field name="title">Driver assigned (SMS to the driver)</field><field name="category">transport</field>
            <field name="send_sms" eval="True"/><field name="dynamic_mobile_field">driver_mobile</field><field name="dynamic_user_field">customs_owner_id</field>
            <field name="internal_subject">Driver assigned to {{name}}</field><field name="internal_body">Driver {{driver}} was assigned to loading {{name}}.</field>
            <field name="sms_body">راننده گرامی، شما برای بارگیری {{name}} از {{factory_id}} به مقصد {{destination}} تعیین شده‌اید.</field>
            <field name="cooldown_minutes">10</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_waybill_recorded" model="itr.notification.event">
            <field name="event_key">shipment.waybill_recorded</field><field name="title">Waybill recorded</field><field name="category">transport</field>
            <field name="dynamic_user_field">customs_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor'))]"/>
            <field name="internal_subject">Waybill {{waybill}} recorded on {{name}}</field><field name="internal_body">Waybill {{waybill}} was recorded on loading {{name}}.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_weighbridge_recorded" model="itr.notification.event">
            <field name="event_key">shipment.weighbridge_recorded</field><field name="title">Weighbridge recorded</field><field name="category">transport</field>
            <field name="dynamic_user_field">customs_owner_id</field>
            <field name="internal_subject">Weighbridge of {{name}} recorded</field><field name="internal_body">Net weight {{net}} t recorded on loading {{name}}; please confirm it.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_bijak_uploaded" model="itr.notification.event">
            <field name="event_key">shipment.bijak_uploaded</field><field name="title">Bijak uploaded</field><field name="category">transport</field>
            <field name="dynamic_user_field">delivery_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor'))]"/>
            <field name="internal_subject">Bijak of {{name}} uploaded</field><field name="internal_body">The declaration and the bijak of loading {{name}} were uploaded and confirmed.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_clearance_recorded" model="itr.notification.event">
            <field name="event_key">shipment.clearance_recorded</field><field name="title">Clearance recorded</field><field name="category">transport</field>
            <field name="dynamic_user_field">delivery_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor'))]"/>
            <field name="internal_subject">Clearance of {{name}} confirmed</field><field name="internal_body">Loading {{name}} was cleared at the border.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_shipment_pod_uploaded" model="itr.notification.event">
            <field name="event_key">shipment.pod_uploaded</field><field name="title">Delivery receipt uploaded</field><field name="category">transport</field>
            <field name="dynamic_user_field">docs_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_transport_supervisor')), (4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">POD of {{name}} uploaded</field><field name="internal_body">The buyer's delivery receipt of loading {{name}} was uploaded; the final freight can now be requested.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_payment_requested" model="itr.notification.event">
            <field name="event_key">payment.requested</field><field name="title">Payment requested</field><field name="category">finance</field>
            <field name="dynamic_user_field">current_owner_id</field><field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Payment request {{name}}</field><field name="internal_body">Payment of {{amount}} to {{payee}} was requested ({{name}}).</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_payment_rejected" model="itr.notification.event">
            <field name="event_key">payment.rejected</field><field name="title">Payment rejected</field><field name="category">finance</field>
            <field name="dynamic_user_field">requested_by_id</field>
            <field name="internal_subject">Payment request {{name}} rejected</field><field name="internal_body">Payment request {{name}} was rejected. Reason: {{reason}}</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_payment_executed" model="itr.notification.event">
            <field name="event_key">payment.executed</field><field name="title">Payment executed</field><field name="category">finance</field>
            <field name="send_sms" eval="True"/><field name="dynamic_user_field">requested_by_id</field>
            <field name="internal_subject">Payment {{name}} executed</field><field name="internal_body">Payment of {{amount}} to {{payee}} was executed ({{name}}).</field>
            <field name="sms_body">پرداخت {{amount}} به {{payee}} بابت {{name}} انجام شد.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_case_closed_manually" model="itr.notification.event">
            <field name="event_key">case.closed_manually</field><field name="title">Loading closed manually</field><field name="category">workflow</field>
            <field name="is_critical" eval="True"/><field name="send_sms" eval="True"/><field name="dynamic_user_field">requested_by_id</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Loading {{name}} closed manually</field><field name="internal_body">Loading {{name}} was closed manually. Reason: {{reason}}</field>
            <field name="sms_body">بارگیری {{name}} با دلیل «{{reason}}» به‌صورت دستی بسته شد.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_factory_debt_recorded" model="itr.notification.event">
            <field name="event_key">factory_debt.recorded</field><field name="title">Factory shortfall recorded</field><field name="category">finance</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor')), (4, ref('itr_core.group_financial_manager'))]"/>
            <field name="internal_subject">Factory shortfall recorded</field><field name="internal_body">A shortfall of {{tonnage}} t was recorded in the factory ledger ({{name}}).</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_factory_debt_settled" model="itr.notification.event">
            <field name="event_key">factory_debt.settled</field><field name="title">Factory shortfall settled</field><field name="category">finance</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor')), (4, ref('itr_core.group_financial_manager'))]"/>
            <field name="internal_subject">Factory shortfall settled</field><field name="internal_body">The factory shortfall {{name}} is fully settled.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
        <record id="event_trade_case_ready_to_close" model="itr.notification.event">
            <field name="event_key">trade_case.ready_to_close</field><field name="title">Trade case ready for the financial close</field><field name="category">workflow</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Trade case {{name}} ready to close</field><field name="internal_body">Every loading of trade case {{name}} is closed; run the financial close.</field>
            <field name="cooldown_minutes">5</field><field name="is_seed" eval="True"/><field name="allow_seed_overwrite" eval="True"/>
        </record>
    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${TRN_DIR}/views/itr_transport_case_ops_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_transport_case_form_ops" model="ir.ui.view">
        <field name="name">itr.transport.case.form.ops</field>
        <field name="model">itr.transport.case</field>
        <field name="inherit_id" ref="itr_transport.view_itr_transport_case_form"/>
        <field name="arch" type="xml">
            <xpath expr="//header/field[@name='state']" position="before">
                <button name="action_authorize_loading" type="object" string="Authorise loading" class="btn-primary"
                        invisible="state != 'pending_review'" groups="itr_core.group_transport_supervisor"/>
                <button name="action_mark_loaded" type="object" string="Loaded" class="btn-primary"
                        invisible="state != 'loading_authorized'" groups="itr_core.group_transport_docs,itr_core.group_transport_supervisor"/>
                <button name="action_depart" type="object" string="Departed"
                        invisible="state != 'loaded'" groups="itr_core.group_transport_docs,itr_core.group_transport_supervisor"/>
                <button name="action_record_weighbridge" type="object" string="Record weighbridge"
                        invisible="state in ('draft','pending_review','loading_authorized','closed','cancelled') or weighbridge_recorded_on"
                        groups="itr_core.group_transport_docs,itr_core.group_transport_supervisor"/>
                <button name="action_confirm_weighbridge" type="object" string="Confirm weighbridge" class="btn-primary"
                        invisible="not weighbridge_recorded_on or weighbridge_confirmed" groups="itr_core.group_customs_officer,itr_core.group_transport_supervisor"/>
                <button name="action_confirm_bijak" type="object" string="Confirm bijak step" class="btn-primary"
                        invisible="not weighbridge_confirmed or bijak_confirmed" groups="itr_core.group_customs_officer,itr_core.group_transport_supervisor"/>
                <button name="action_confirm_clearance" type="object" string="Confirm clearance" class="btn-primary"
                        invisible="not bijak_confirmed or clearance_confirmed" groups="itr_core.group_customs_officer,itr_core.group_transport_supervisor"/>
                <button name="action_settle" type="object" string="Settle (L4)"
                        invisible="state not in ('waiting_payment','delivered')" groups="itr_core.group_transport_delivery,itr_core.group_transport_supervisor,itr_core.group_finance_supervisor"/>
                <button name="action_close" type="object" string="Close (10/10)" class="btn-primary"
                        invisible="state not in ('waiting_payment','delivered','settled')" groups="itr_core.group_finance_supervisor,itr_core.group_transport_supervisor"/>
                <button name="action_manual_close" type="object" string="Manual close with reason"
                        invisible="state not in ('waiting_payment','delivered','settled')" context="{'itr_reason': 'Manual close from form'}"
                        groups="itr_core.group_finance_supervisor,itr_core.group_transport_supervisor"/>
                <button name="action_reopen" type="object" string="Reopen (BR-123)"
                        invisible="state != 'closed'" context="{'itr_reason': 'Reopened from form'}"
                        groups="itr_core.group_financial_manager,itr_base.group_itr_validation_override"/>
                <!-- fields referenced by the button modifiers must be present in the arch -->
                <field name="weighbridge_recorded_on" invisible="1"/>
                <field name="weighbridge_confirmed" invisible="1"/>
                <field name="bijak_confirmed" invisible="1"/>
                <field name="clearance_confirmed" invisible="1"/>
            </xpath>
            <xpath expr="//div[@name='button_box']" position="inside">
                <button name="action_open_driver_history" type="object" class="oe_stat_button" icon="fa-history" invisible="not driver_id">
                    <field name="duplicate_driver_count" widget="statinfo" string="Driver history"/>
                </button>
            </xpath>
            <xpath expr="//page[@name='snapshot']" position="after">
                <page string="Documents and fleet" name="docs">
                    <group>
                        <group string="Owners">
                            <field name="docs_owner_id" readonly="1"/>
                            <field name="customs_owner_id" readonly="1"/>
                            <field name="delivery_owner_id" readonly="1"/>
                            <field name="buyer_credit_confirmed"/>
                        </group>
                        <group string="Driver and fleet">
                            <field name="driver_id"/>
                            <field name="driver_mobile"/>
                            <field name="driver_smart_card_status"/>
                            <field name="vehicle_id"/>
                            <field name="duplicate_vehicle_count"/>
                            <field name="carrier_id"/>
                        </group>
                    </group>
                    <group>
                        <group string="Waybill">
                            <field name="waybill_issuer"/>
                            <field name="waybill_number"/>
                            <field name="waybill_date"/>
                            <field name="waybill_tonnage"/>
                            <field name="waybill_total_freight"/>
                            <field name="waybill_currency_id"/>
                            <field name="waybill_freight_base" readonly="1"/>
                            <field name="insurance_amount"/>
                            <field name="insurance_confirmed"/>
                            <field name="letter_match_confirmed"/>
                        </group>
                        <group string="Weighbridge at origin">
                            <field name="gross_weight"/>
                            <field name="tare_weight"/>
                            <field name="net_weight" readonly="1"/>
                            <field name="weighbridge_ticket_no"/>
                            <field name="weighbridge_file" filename="weighbridge_file_name"/>
                            <field name="weighbridge_file_name" invisible="1"/>
                            <field name="weighbridge_recorded_by_id" readonly="1"/>
                            <field name="weighbridge_confirmed" readonly="1"/>
                            <field name="weighbridge_confirmed_by_id" readonly="1"/>
                            <field name="effective_tonnage" readonly="1"/>
                        </group>
                    </group>
                    <group>
                        <group string="Packing list">
                            <field name="packing_list_done"/>
                            <field name="packing_date"/>
                            <field name="packing_file" filename="packing_file_name"/>
                            <field name="packing_file_name" invisible="1"/>
                            <field name="docs_reviewed_payment"/>
                        </group>
                        <group string="Manual tonnage (documented)">
                            <field name="manual_effective_tonnage"/>
                            <field name="manual_effective_reason"/>
                            <field name="no_more_dispatch_planned"/>
                        </group>
                    </group>
                </page>
                <page string="Border and clearance" name="customs">
                    <group>
                        <group string="Driver and smart card">
                            <field name="driver_confirmed"/>
                            <field name="smart_card_checked_on"/>
                        </group>
                        <group string="Bijak (OPS-024)">
                            <field name="needs_bijak"/>
                            <field name="declaration_file" filename="declaration_file_name"/>
                            <field name="declaration_file_name" invisible="1"/>
                            <field name="bijak_file" filename="bijak_file_name"/>
                            <field name="bijak_file_name" invisible="1"/>
                            <field name="bijak_confirmed" readonly="1"/>
                        </group>
                    </group>
                    <group>
                        <group string="Clearance">
                            <field name="customs_broker_id"/>
                            <field name="border_agent_id"/>
                            <field name="clearance_status"/>
                            <field name="clearance_date"/>
                            <field name="clearance_hour" widget="float_time"/>
                            <field name="clearance_confirmed" readonly="1"/>
                        </group>
                    </group>
                    <field name="coordination_log_ids">
                        <list editable="bottom">
                            <field name="logged_on" readonly="1"/>
                            <field name="kind"/>
                            <field name="note"/>
                            <field name="logged_by_id" readonly="1"/>
                        </list>
                    </field>
                </page>
                <page string="Delivery and settlement" name="delivery">
                    <group>
                        <group string="Delivery">
                            <field name="docs_final_confirmed"/>
                            <field name="delivery_receipt" filename="delivery_receipt_name"/>
                            <field name="delivery_receipt_name" invisible="1"/>
                            <field name="delivery_receipt_by_id" readonly="1"/>
                            <field name="delivered_on"/>
                            <field name="payee_sheba"/>
                            <field name="payee_sheba_masked"/>
                        </group>
                        <group string="Freight anchor (FIN-021)">
                            <field name="waybill_freight_base" readonly="1"/>
                            <field name="advance_paid_base" readonly="1"/>
                            <field name="final_freight_due" readonly="1"/>
                            <field name="freight_settled_base" readonly="1"/>
                            <field name="finance_settled"/>
                        </group>
                    </group>
                    <separator string="Cost lines (commitments, G06)"/>
                    <field name="cost_line_ids" context="{'default_transport_case_id': id}">
                        <list editable="bottom">
                            <field name="charge_type_id"/>
                            <field name="category"/>
                            <field name="description"/>
                            <field name="amount"/>
                            <field name="currency_id"/>
                            <field name="base_amount" readonly="1"/>
                            <field name="payee_type"/>
                            <field name="payee_name"/>
                            <field name="payee_sheba_masked"/>
                            <field name="installment_no"/>
                            <field name="payment_status" readonly="1"/>
                            <button name="action_request_payment" type="object" string="Request payment" icon="fa-money" invisible="payment_status != 'recorded'"/>
                        </list>
                    </field>
                    <group string="Roll-ups (read-only, single money engine)">
                        <group>
                            <field name="freight_cost" readonly="1"/>
                            <field name="customs_cost" readonly="1"/>
                            <field name="clearance_cost" readonly="1"/>
                            <field name="insurance_cost" readonly="1"/>
                        </group>
                        <group>
                            <field name="origin_cost" readonly="1"/>
                            <field name="other_cost" readonly="1"/>
                            <field name="other_cost_description"/>
                            <field name="total_cost" readonly="1"/>
                            <field name="total_settled" readonly="1"/>
                        </group>
                    </group>
                    <separator string="Payment requests and executions"/>
                    <field name="payment_request_ids" readonly="1">
                        <list>
                            <field name="name"/><field name="charge_type_id"/><field name="payee_name"/><field name="installment_no"/>
                            <field name="amount"/><field name="currency_id"/><field name="state" widget="badge"/><field name="current_owner_id"/>
                        </list>
                    </field>
                    <field name="payment_execution_ids" readonly="1">
                        <list>
                            <field name="executed_on"/><field name="execution_id"/><field name="payee_name"/><field name="amount"/>
                            <field name="currency_id"/><field name="base_amount"/><field name="bank_reference"/><field name="state"/><field name="is_reversal"/>
                        </list>
                    </field>
                </page>
                <page string="Closing checklist" name="closing">
                    <group>
                        <group>
                            <field name="checklist_progress" widget="progressbar"/>
                            <field name="chk_purchase"/>
                            <field name="chk_sales"/>
                            <field name="chk_driver"/>
                            <field name="chk_waybill"/>
                            <field name="chk_weighbridge"/>
                        </group>
                        <group>
                            <field name="chk_bijak"/>
                            <field name="chk_clearance"/>
                            <field name="chk_delivery"/>
                            <field name="chk_payments"/>
                            <field name="finance_approved"/>
                        </group>
                    </group>
                    <group>
                        <group>
                            <field name="closed_by_id" readonly="1"/>
                            <field name="closed_on" readonly="1"/>
                            <field name="manual_close_reason" readonly="1"/>
                        </group>
                        <group>
                            <field name="reopen_count" readonly="1"/>
                            <field name="reopen_reason" readonly="1"/>
                        </group>
                    </group>
                </page>
                <page string="Documents" name="documents">
                    <field name="document_ids" context="{'default_transport_case_id': id}">
                        <list editable="bottom">
                            <field name="document_type_id"/>
                            <field name="file" filename="filename"/>
                            <field name="filename"/>
                            <field name="uploaded_by_id" readonly="1"/>
                            <field name="uploaded_on" readonly="1"/>
                            <field name="note"/>
                        </list>
                    </field>
                </page>
            </xpath>
        </field>
    </record>

    <record id="view_itr_transport_case_search_ops" model="ir.ui.view">
        <field name="name">itr.transport.case.search.ops</field>
        <field name="model">itr.transport.case</field>
        <field name="inherit_id" ref="itr_transport.view_itr_transport_case_search"/>
        <field name="arch" type="xml">
            <xpath expr="//filter[@name='my_loadings']" position="after">
                <filter name="my_tab_loadings" string="My tab loadings"
                        domain="['|', '|', ('docs_owner_id', '=', uid), ('customs_owner_id', '=', uid), ('delivery_owner_id', '=', uid)]"/>
                <filter name="missing_pod" string="Missing POD" domain="[('delivery_receipt', '=', False), ('state', 'not in', ('closed', 'cancelled'))]"/>
                <filter name="missing_waybill" string="Missing waybill" domain="[('waybill_number', '=', False), ('state', 'not in', ('closed', 'cancelled'))]"/>
            </xpath>
            <xpath expr="//field[@name='customer_id']" position="after">
                <field name="waybill_number"/>
                <field name="driver_id"/>
                <field name="vehicle_id"/>
            </xpath>
        </field>
    </record>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/views/itr_transport_phase6_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- charge types -->
    <record id="view_itr_charge_type_list" model="ir.ui.view">
        <field name="name">itr.charge.type.list</field>
        <field name="model">itr.charge.type</field>
        <field name="arch" type="xml">
            <list string="Charge Types" editable="bottom">
                <field name="sequence" widget="handle"/>
                <field name="name"/><field name="code"/><field name="category"/>
                <field name="is_advance"/><field name="requires_pod"/><field name="counts_in_freight_anchor"/>
                <field name="payee_type"/><field name="calc_mode"/><field name="default_currency_id"/><field name="active"/>
            </list>
        </field>
    </record>
    <record id="action_itr_charge_type" model="ir.actions.act_window">
        <field name="name">Charge Types</field>
        <field name="res_model">itr.charge.type</field>
        <field name="view_mode">list</field>
    </record>

    <!-- document types -->
    <record id="view_itr_document_type_list" model="ir.ui.view">
        <field name="name">itr.document.type.list</field>
        <field name="model">itr.document.type</field>
        <field name="arch" type="xml">
            <list string="Document Types" editable="bottom">
                <field name="sequence" widget="handle"/><field name="name"/><field name="code"/><field name="is_financial"/><field name="active"/>
            </list>
        </field>
    </record>
    <record id="action_itr_document_type" model="ir.actions.act_window">
        <field name="name">Document Types</field>
        <field name="res_model">itr.document.type</field>
        <field name="view_mode">list</field>
    </record>

    <!-- cost lines -->
    <record id="view_itr_cost_line_list" model="ir.ui.view">
        <field name="name">itr.cost.line.list</field>
        <field name="model">itr.cost.line</field>
        <field name="arch" type="xml">
            <list string="Cost Lines" create="false">
                <field name="transport_case_id"/><field name="charge_type_id"/><field name="category"/>
                <field name="amount"/><field name="currency_id"/><field name="base_amount"/>
                <field name="payee_name"/><field name="payee_sheba_masked"/><field name="installment_no"/>
                <field name="payment_status" widget="badge"/><field name="recorded_by_id"/>
            </list>
        </field>
    </record>
    <record id="action_itr_cost_line" model="ir.actions.act_window">
        <field name="name">Cost Lines</field>
        <field name="res_model">itr.cost.line</field>
        <field name="view_mode">list</field>
    </record>

    <!-- payment requests -->
    <record id="view_itr_payment_request_form" model="ir.ui.view">
        <field name="name">itr.payment.request.form</field>
        <field name="model">itr.payment.request</field>
        <field name="arch" type="xml">
            <form string="Payment Request" create="false">
                <header>
                    <button name="action_execute" type="object" string="Execute payment" class="btn-primary"
                            invisible="state != 'requested'" groups="itr_core.group_finance_supervisor"/>
                    <button name="action_reject" type="object" string="Reject"
                            invisible="state != 'requested'" groups="itr_core.group_finance_supervisor"
                            context="{'itr_reason': 'Rejected from form'}"/>
                    <field name="state" widget="statusbar" statusbar_visible="requested,executed"/>
                </header>
                <sheet>
                    <div class="oe_title"><h1><field name="name" readonly="1"/></h1></div>
                    <group>
                        <group string="Key A (FIN-023)">
                            <field name="transport_case_id"/><field name="waybill_number"/><field name="payee_name"/>
                            <field name="payee_sheba_masked"/><field name="charge_type_id"/><field name="installment_no"/>
                        </group>
                        <group string="Money event">
                            <field name="amount"/><field name="currency_id"/><field name="exchange_rate"/><field name="base_amount"/>
                            <field name="executed_base_amount"/><field name="current_owner_id" readonly="1"/><field name="owner_deadline" readonly="1"/>
                        </group>
                    </group>
                    <group>
                        <field name="requested_by_id"/><field name="requested_on"/><field name="reject_reason"/>
                    </group>
                    <field name="execution_ids" readonly="1">
                        <list>
                            <field name="executed_on"/><field name="execution_id"/><field name="amount"/><field name="currency_id"/>
                            <field name="base_amount"/><field name="bank_reference"/><field name="executed_by_id"/><field name="state"/><field name="is_reversal"/>
                            <button name="action_reverse" type="object" string="Reverse" icon="fa-undo" invisible="state != 'done' or is_reversal"
                                    context="{'itr_reason': 'Reversed from form'}" groups="itr_core.group_finance_supervisor"/>
                        </list>
                    </field>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>
    <record id="view_itr_payment_request_list" model="ir.ui.view">
        <field name="name">itr.payment.request.list</field>
        <field name="model">itr.payment.request</field>
        <field name="arch" type="xml">
            <list string="Payment Requests" create="false">
                <field name="name"/><field name="transport_case_id"/><field name="waybill_number"/><field name="charge_type_id"/>
                <field name="payee_name"/><field name="installment_no"/><field name="amount"/><field name="currency_id"/>
                <field name="current_owner_id"/><field name="state" widget="badge"/>
            </list>
        </field>
    </record>
    <record id="view_itr_payment_request_search" model="ir.ui.view">
        <field name="name">itr.payment.request.search</field>
        <field name="model">itr.payment.request</field>
        <field name="arch" type="xml">
            <search string="Payment Requests">
                <field name="name"/><field name="waybill_number"/><field name="payee_name"/><field name="transport_case_id"/>
                <filter name="my_requests" string="On my desk" domain="[('current_owner_id', '=', uid)]"/>
                <filter name="pending" string="Pending" domain="[('state', '=', 'requested')]"/>
                <filter name="group_state" string="State" context="{'group_by': 'state'}"/>
            </search>
        </field>
    </record>
    <record id="action_itr_payment_request" model="ir.actions.act_window">
        <field name="name">Payment Requests</field>
        <field name="res_model">itr.payment.request</field>
        <field name="view_mode">list,form</field>
        <field name="context">{'search_default_pending': 1}</field>
    </record>

    <!-- payment executions (G07: the only source of the payments report) -->
    <record id="view_itr_payment_execution_list" model="ir.ui.view">
        <field name="name">itr.payment.execution.list</field>
        <field name="model">itr.payment.execution</field>
        <field name="arch" type="xml">
            <list string="Payment Executions" create="false" edit="false" delete="false">
                <field name="executed_on"/><field name="execution_id"/><field name="transport_case_id"/><field name="payment_request_id"/>
                <field name="payee_name"/><field name="payee_sheba_masked"/><field name="amount"/><field name="currency_id"/>
                <field name="base_amount"/><field name="bank_reference"/><field name="executed_by_id"/><field name="state"/><field name="is_reversal"/>
            </list>
        </field>
    </record>
    <record id="action_itr_payment_execution" model="ir.actions.act_window">
        <field name="name">Payment Executions</field>
        <field name="res_model">itr.payment.execution</field>
        <field name="view_mode">list</field>
    </record>

    <!-- shortfall: settlements page on the phase-4 form (inheritance) -->
    <record id="view_itr_factory_shortfall_form_settlements" model="ir.ui.view">
        <field name="name">itr.factory.shortfall.form.settlements</field>
        <field name="model">itr.factory.shortfall</field>
        <field name="inherit_id" ref="itr_core.view_itr_factory_shortfall_form"/>
        <field name="arch" type="xml">
            <xpath expr="//field[@name='notes']" position="before">
                <group string="Settlement (BR-122)">
                    <field name="settled_tonnage" readonly="1"/>
                    <field name="remaining_tonnage" readonly="1"/>
                    <field name="settled_amount_base" readonly="1"/>
                    <field name="age_days" readonly="1"/>
                </group>
                <field name="settlement_ids" context="{'default_shortfall_id': id}">
                    <list editable="bottom">
                        <field name="settlement_date"/><field name="settled_tonnage"/><field name="settled_amount_base"/>
                        <field name="compensation_case_id"/><field name="settled_by_id" readonly="1"/><field name="note"/>
                    </list>
                </field>
            </xpath>
        </field>
    </record>

    <!-- trade case: loadings smart button + close action (inheritance of the phase-4 form) -->
    <record id="view_itr_trade_case_form_transport" model="ir.ui.view">
        <field name="name">itr.trade.case.form.transport</field>
        <field name="model">itr.trade.case</field>
        <!-- multi-level inheritance: the button_box is added by the phase-5 view -->
        <field name="inherit_id" ref="itr_core.view_itr_trade_case_form_phase5"/>
        <field name="arch" type="xml">
            <xpath expr="//header/field[@name='state']" position="before">
                <button name="action_close_case" type="object" string="Financial close" class="btn-primary"
                        invisible="state != 'slips_issued' or not loadings_all_closed" groups="itr_core.group_finance_supervisor"/>
            </xpath>
            <xpath expr="//div[@name='button_box']" position="inside">
                <button name="action_open_loadings" type="object" class="oe_stat_button" icon="fa-truck">
                    <field name="transport_case_count" widget="statinfo" string="Loadings"/>
                </button>
            </xpath>
            <xpath expr="//field[@name='estimated_profit_base']" position="before">
                <field name="operational_cost_base" readonly="1"/>
                <field name="total_settled_base" readonly="1"/>
                <field name="effective_tonnage_total" readonly="1"/>
                <field name="loadings_all_closed" readonly="1"/>
            </xpath>
        </field>
    </record>
</odoo>
XMLEOF

write_utf8 "${TRN_DIR}/views/itr_transport_phase6_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <menuitem id="menu_itr_payment_request" name="Payment Requests" parent="itr_transport.menu_itr_transport_root"
              action="action_itr_payment_request" sequence="20"/>
    <menuitem id="menu_itr_payment_execution" name="Payment Executions" parent="itr_transport.menu_itr_transport_root"
              action="action_itr_payment_execution" sequence="30"
              groups="itr_core.group_finance_supervisor,itr_core.group_financial_manager,itr_core.group_ceo,itr_core.group_auditor,itr_core.group_transport_supervisor"/>
    <menuitem id="menu_itr_cost_line" name="Cost Lines" parent="itr_transport.menu_itr_transport_root"
              action="action_itr_cost_line" sequence="40"/>
    <menuitem id="menu_itr_transport_config" name="Configuration" parent="itr_transport.menu_itr_transport_root" sequence="90"
              groups="itr_core.group_transport_supervisor,itr_core.group_finance_supervisor,itr_core.group_financial_manager,itr_core.group_ceo"/>
    <menuitem id="menu_itr_charge_type" name="Charge Types" parent="menu_itr_transport_config" action="action_itr_charge_type" sequence="10"/>
    <menuitem id="menu_itr_document_type" name="Document Types" parent="menu_itr_transport_config" action="action_itr_document_type" sequence="20"/>
</odoo>
XMLEOF

# ------------------------------------------------------------------ tests --
write_utf8 "${TRN_DIR}/tests/test_transport_ops_phase6.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 6 automated tests (Q04/G01: real seeded users only).

Positive (plan): three specialists on three tabs of one loading without lost
update; full three-stage payment cycle; shortage -> manual close -> shortfall
row -> partial settlement. Negative (plan): duplicate waybill, duplicate
payment request (key A), final freight before POD, close with 9/10, transport
user setting finance flags / executing, gross < tare and bijak without files.
"""
import base64
import uuid

from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged
from odoo.tools import mute_logger

from .common import ItrTransportCase

PDF = base64.b64encode(b"%PDF-1.4 TEST")


@tagged("post_install", "-at_install", "itr_transport")
class TestItrTransportOpsPhase6(ItrTransportCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.env = cls.env(context=dict(cls.env.context, itr_notify_sync=True))
        cls.carrier = cls.env["res.partner"].sudo().create({"name": "TEST carrier", "is_company": True, "is_shipping_line": True})
        cls.broker = cls.env["res.partner"].sudo().create({"name": "TEST broker", "is_company": True, "is_customs_agent": True})
        cls.charge = {c.code: c for c in cls.env["itr.charge.type"].search([])}
        cls.seq = 0

    # ------------------------------------------------------------- helpers
    def _driver_vehicle(self):
        type(self).seq += 1
        driver = self.env["itr.driver"].with_user(self.transport_docs).create({
            "name": "TEST driver %s" % self.seq, "nationality": "iranian",
            "national_id": "0084575948", "mobile": "09123456789"})
        vehicle = self.env["itr.vehicle"].with_user(self.transport_docs).create({
            "plate_number": "12 \u0628 %03d \u0627\u06cc\u0631\u0627\u0646 67" % (100 + self.seq), "plate_type": "iranian"})
        return driver, vehicle

    def _authorized(self, tonnage=100.0):
        case, slip, cases = self._handed_over(tonnage)
        tc = cases[:1].with_context(itr_notify_sync=True)
        tc.with_user(self.receivables).write({"buyer_credit_confirmed": True})
        tc.with_user(self.transport_sup).action_authorize_loading()
        return case, slip, tc

    def _waybill(self, tc, number, freight=50_000_000.0):
        driver, vehicle = self._driver_vehicle()
        tc.with_user(self.transport_docs).write({
            "driver_id": driver.id, "vehicle_id": vehicle.id, "carrier_id": self.carrier.id,
            "waybill_issuer": "TEST carrier", "waybill_number": number, "waybill_tonnage": 100.0,
            "waybill_total_freight": freight, "insurance_amount": 1_000_000.0,
            "insurance_confirmed": True, "letter_match_confirmed": True})
        return tc

    def _to_waiting_payment(self, tc, number, net=96.0, needs_bijak="yes"):
        self._waybill(tc, number)
        tc.with_user(self.transport_docs).action_mark_loaded()
        tc.with_user(self.transport_docs).action_depart()
        tc.with_user(self.transport_docs).write({"gross_weight": net + 25.0, "tare_weight": 25.0, "weighbridge_ticket_no": "WT-%s" % number})
        tc.with_user(self.transport_docs).action_record_weighbridge()
        tc.with_user(self.customs).write({"needs_bijak": needs_bijak, "driver_confirmed": True})
        tc.with_user(self.customs).action_confirm_weighbridge()
        if needs_bijak == "yes":
            tc.with_user(self.customs).write({"declaration_file": PDF, "declaration_file_name": "d.pdf",
                                              "bijak_file": PDF, "bijak_file_name": "b.pdf"})
            tc.with_user(self.customs).action_confirm_bijak()
        tc.with_user(self.customs).write({"customs_broker_id": self.broker.id, "clearance_status": "cleared"})
        tc.with_user(self.customs).action_confirm_clearance()
        self.assertEqual(tc.state, "waiting_payment")
        return tc

    def _cost(self, tc, code, amount, user, payee="TEST payee", installment=1):
        return self.env["itr.cost.line"].with_user(user).create({
            "transport_case_id": tc.id, "charge_type_id": self.charge[code].id,
            "amount": amount, "payee_name": payee, "installment_no": installment})

    def _pay(self, line, user_request, bank="TEST-REF"):
        request = line.with_user(user_request).action_request_payment()
        execution = request.with_user(self.fin_sup).action_execute(bank_reference=bank)
        return request, execution

    def _pod(self, tc):
        tc.with_user(self.delivery).write({"delivery_receipt": PDF, "delivery_receipt_name": "pod.pdf"})

    def _full_payments(self, tc):
        adv = self._cost(tc, "advance_freight", 20_000_000.0, self.delivery, payee="TEST driver")
        self._pay(adv, self.delivery)
        cus = self._cost(tc, "customs_duty", 3_000_000.0, self.customs, payee="TEST customs")
        cle = self._cost(tc, "clearance_fee", 1_500_000.0, self.customs, payee="TEST broker")
        self._pay(cus, self.customs)
        self._pay(cle, self.customs)
        self._pod(tc)
        fin = self._cost(tc, "final_freight", 30_000_000.0, self.delivery, payee="TEST driver")
        self._pay(fin, self.delivery)
        return adv, cus, cle, fin

    # ============================================================ positive
    def test_10_three_specialists_parallel_tabs_no_lost_update(self):
        case, slip, tc = self._authorized()
        driver, vehicle = self._driver_vehicle()
        tc.with_user(self.transport_docs).write({"driver_id": driver.id, "vehicle_id": vehicle.id})
        tc.with_user(self.customs).write({"needs_bijak": "no", "driver_confirmed": True})
        tc.with_user(self.delivery).write({"payee_sheba": "IR930150000001351800087201"})
        tc.invalidate_recordset()
        self.assertEqual(tc.driver_id, driver)
        self.assertEqual(tc.needs_bijak, "no")
        self.assertTrue(tc.chk_driver)
        self.assertEqual(tc.payee_sheba_masked, "IR93****7201", "VAL-008 single mask policy")
        self.assertTrue(tc.docs_owner_id and tc.customs_owner_id and tc.delivery_owner_id, "three tab owners (C1)")
        # cross-tab writes are refused on the server (G14)
        with self.assertRaises(UserError):
            tc.with_user(self.transport_docs).write({"needs_bijak": "yes"})
        with self.assertRaises(UserError):
            tc.with_user(self.customs).write({"delivery_receipt": PDF, "delivery_receipt_name": "x.pdf"})
        with self.assertRaises(UserError):
            tc.with_user(self.delivery).write({"waybill_number": "X"})
        logs = self.env["itr.notification.dispatch.log"].sudo().search([
            ("event_key", "=", "shipment.driver_assigned"), ("res_id", "=", tc.id)])
        self.assertTrue(logs, "driver SMS event dispatched (simulated in test mode)")

    def test_11_full_three_stage_payment_cycle(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-1001")
        self.assertAlmostEqual(tc.effective_tonnage, 96.0, places=3)
        self.assertAlmostEqual(case.item_ids[0].effective_tonnage, 96.0, places=3, msg="OPS-023 roll-up")
        adv, cus, cle, fin = self._full_payments(tc)
        self.assertEqual(adv.payment_status, "paid")
        self.assertEqual(cus.category, "customs")
        self.assertEqual(cle.category, "clearance", "G05: two independent lines")
        self.assertAlmostEqual(tc.freight_settled_base, 50_000_000.0, places=0)
        self.assertAlmostEqual(tc.final_freight_due, 30_000_000.0, places=0, msg="FIN-021 anchor - advance")
        self.assertEqual(tc.state, "delivered")
        self.assertTrue(tc.chk_payments, "BR-101: commitments fully allocated")
        totals = self.env["itr.money.engine"].transport_totals(tc)
        self.assertAlmostEqual(totals["total_cost"], 54_500_000.0, places=0)
        self.assertAlmostEqual(totals["total_settled"], 54_500_000.0, places=0)
        self.assertAlmostEqual(case.operational_cost_base, 54_500_000.0, places=0, msg="single money engine on the case")
        executions = tc.payment_execution_ids
        self.assertEqual(len(executions), 4)
        self.assertEqual(len(set(executions.mapped("execution_id"))), 4, "key B")
        # closing 10/10
        tc.with_user(self.delivery).write({"docs_final_confirmed": True})
        tc.with_user(self.fin_sup).write({"finance_settled": True, "chk_purchase": True, "chk_sales": True, "finance_approved": True})
        tc.with_user(self.delivery).action_settle()
        self.assertEqual(tc.state, "settled")
        tc.with_user(self.fin_sup).action_close()
        self.assertEqual(tc.state, "closed")
        self.assertTrue(case.loadings_all_closed)
        case.with_user(self.fin_sup).action_close_case()
        self.assertEqual(case.state, "closed")

    def test_12_shortage_manual_close_shortfall_and_partial_settlement(self):
        case, slip, tc = self._authorized(100.0)
        self._to_waiting_payment(tc, "WB-1002", net=96.0)
        self._full_payments(tc)
        tc.with_user(self.transport_sup).write({"no_more_dispatch_planned": True})
        tc.with_user(self.fin_sup).write({"finance_approved": True})
        tc.with_user(self.fin_sup).action_manual_close(reason="TEST factory loaded 96 of 100 t")
        self.assertEqual(tc.state, "closed")
        shortfall = self.env["itr.factory.shortfall"].search([("trade_case_item_id", "=", case.item_ids[0].id)])
        self.assertEqual(len(shortfall), 1, "BR-121: one row per purchase item")
        self.assertAlmostEqual(shortfall.shortfall_tonnage, 4.0, places=3)
        self.assertEqual(shortfall.state, "open")
        Settlement = self.env["itr.factory.shortfall.settlement"].with_user(self.fin_sup)
        Settlement.create({"shortfall_id": shortfall.id, "settled_tonnage": 1.5, "settled_amount_base": 150.0})
        self.assertEqual(shortfall.state, "partially_settled")
        Settlement.create({"shortfall_id": shortfall.id, "settled_tonnage": 2.5, "compensation_case_id": case.id})
        self.assertEqual(shortfall.state, "settled")
        with self.assertRaises(ValidationError):
            Settlement.create({"shortfall_id": shortfall.id, "settled_tonnage": 0.1})
        logs = self.env["itr.notification.dispatch.log"].sudo().search([("event_key", "=", "case.closed_manually"), ("res_id", "=", tc.id)])
        self.assertTrue(logs)

    # ============================================================ negative
    @mute_logger("odoo.sql_db")
    def test_20_duplicate_waybill_refused(self):
        case, slip, tc1 = self._authorized(50.0)
        case2, slip2, tc2 = self._authorized(50.0)
        self._waybill(tc1, "WB-DUP")
        with self.assertRaises(ValidationError):
            self._waybill(tc2, "WB-DUP")

    def test_21_duplicate_payment_request_key_a(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2001")
        line1 = self._cost(tc, "customs_duty", 1_000_000.0, self.customs, payee="TEST customs", installment=1)
        line2 = self._cost(tc, "customs_duty", 1_000_000.0, self.customs, payee="TEST customs", installment=1)
        line1.with_user(self.customs).action_request_payment()
        with self.assertRaises(ValidationError):
            line2.with_user(self.customs).action_request_payment()
        line2.with_user(self.customs).write({"installment_no": 2})  # legitimate partial payment
        self.assertTrue(line2.with_user(self.customs).action_request_payment())

    def test_22_final_freight_locked_until_pod(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2002")
        fin = self._cost(tc, "final_freight", 30_000_000.0, self.delivery, payee="TEST driver")
        with self.assertRaises(UserError):
            fin.with_user(self.delivery).action_request_payment()
        self._pod(tc)
        self.assertTrue(fin.with_user(self.delivery).action_request_payment())

    def test_23_close_with_nine_of_ten_is_impossible(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2003")
        adv = self._cost(tc, "advance_freight", 20_000_000.0, self.delivery, payee="TEST driver")
        self._pay(adv, self.delivery)   # a partial advance is paid ...
        self._pod(tc)
        tc.with_user(self.delivery).write({"docs_final_confirmed": True})
        tc.with_user(self.fin_sup).write({"finance_settled": True, "chk_purchase": True, "chk_sales": True, "finance_approved": True})
        self.assertFalse(tc.chk_payments, "BR-101: one positive payment never turns chk_payments green")
        with self.assertRaises(UserError):
            tc.with_user(self.fin_sup).action_close()
        fin = self._cost(tc, "final_freight", 30_000_000.0, self.delivery, payee="TEST driver")
        self._pay(fin, self.delivery)
        self.assertTrue(tc.chk_payments)
        tc.with_user(self.fin_sup).write({"finance_approved": False})
        with self.assertRaises(UserError):
            tc.with_user(self.fin_sup).action_close()

    def test_24_transport_user_cannot_set_finance_flags_or_execute(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2004")
        with self.assertRaises(UserError):
            tc.with_user(self.transport_docs).write({"finance_approved": True})
        with self.assertRaises(UserError):
            tc.with_user(self.delivery).write({"finance_settled": True})
        with self.assertRaises(UserError):
            tc.sudo().write({"finance_approved": True})
        adv = self._cost(tc, "advance_freight", 1_000_000.0, self.delivery, payee="TEST driver")
        request = adv.with_user(self.delivery).action_request_payment()
        with self.assertRaises((AccessError, UserError)):
            request.with_user(self.delivery).action_execute()
        with self.assertRaises((AccessError, UserError)):
            adv.with_user(self.delivery).write({"payment_status": "paid"})
        with self.assertRaises((AccessError, UserError)):
            self.env["itr.payment.execution"].with_user(self.delivery).create({
                "payment_request_id": request.id, "amount": 1.0, "currency_id": self.env.company.currency_id.id})

    def test_25_weights_and_bijak_guards(self):
        case, slip, tc = self._authorized()
        self._waybill(tc, "WB-2005")
        with self.assertRaises(ValidationError):
            tc.with_user(self.transport_docs).write({"gross_weight": 20.0, "tare_weight": 25.0})
        tc.with_user(self.transport_docs).action_mark_loaded()
        tc.with_user(self.transport_docs).write({"gross_weight": 120.0, "tare_weight": 25.0})
        tc.with_user(self.transport_docs).action_record_weighbridge()
        with self.assertRaises(UserError):
            tc.with_user(self.transport_docs).action_confirm_weighbridge()  # same person - 6.5
        tc.with_user(self.customs).write({"needs_bijak": "yes"})
        tc.with_user(self.customs).action_confirm_weighbridge()
        self.assertAlmostEqual(tc.effective_tonnage, 95.0, places=3)
        with self.assertRaises(UserError):
            tc.with_user(self.customs).action_confirm_bijak()  # no files
        tc.with_user(self.customs).write({"declaration_file": PDF, "declaration_file_name": "d.pdf"})
        with self.assertRaises(UserError):
            tc.with_user(self.customs).action_confirm_bijak()  # only one of two
        tc.with_user(self.customs).write({"bijak_file": PDF, "bijak_file_name": "b.pdf"})
        tc.with_user(self.customs).action_confirm_bijak()
        self.assertTrue(tc.chk_bijak)

    @mute_logger("odoo.sql_db")
    def test_26_key_b_and_reversal(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2006")
        adv = self._cost(tc, "advance_freight", 5_000_000.0, self.delivery, payee="TEST driver")
        request = adv.with_user(self.delivery).action_request_payment()
        fixed_id = str(uuid.uuid4())
        execution = request.with_user(self.fin_sup).action_execute(execution_id=fixed_id)
        with self.assertRaises(UserError):
            request.with_user(self.fin_sup).action_execute()  # double click
        with self.assertRaises(Exception):
            with self.env.cr.savepoint():
                self.env["itr.payment.execution"].with_user(self.fin_sup).with_context(itr_payment_engine=True).create({
                    "payment_request_id": request.id, "execution_id": fixed_id, "amount": 1.0,
                    "currency_id": self.env.company.currency_id.id})
        with self.assertRaises(UserError):
            execution.with_user(self.fin_sup).unlink()
        reversal = execution.with_user(self.fin_sup).action_reverse(reason="TEST wrong account")
        self.assertTrue(reversal.is_reversal)
        self.assertEqual(execution.state, "reversed")
        self.assertEqual(request.state, "requested")
        self.assertEqual(adv.payment_status, "requested")
        self.assertAlmostEqual(tc.total_settled, 0.0, places=0)

    def test_27_freight_anchor_overflow_refused(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2007")
        self._cost(tc, "advance_freight", 45_000_000.0, self.delivery, payee="TEST driver")
        with self.assertRaises(ValidationError):
            self._cost(tc, "advance_freight", 10_000_000.0, self.delivery, payee="TEST driver 2")

    def test_28_reopen_requires_special_group_and_reason(self):
        case, slip, tc = self._authorized()
        self._to_waiting_payment(tc, "WB-2008")
        self._full_payments(tc)
        tc.with_user(self.delivery).write({"docs_final_confirmed": True})
        tc.with_user(self.fin_sup).write({"finance_settled": True, "chk_purchase": True, "chk_sales": True, "finance_approved": True})
        tc.with_user(self.fin_sup).action_close()
        with self.assertRaises(UserError):
            tc.with_user(self.fin_sup).action_reopen(reason="TEST not allowed")
        with self.assertRaises(UserError):
            tc.with_user(self.fin_mgr).action_reopen(reason="")
        tc.with_user(self.fin_mgr).action_reopen(reason="TEST wrong weighbridge")
        self.assertEqual(tc.state, "delivered")
        self.assertEqual(tc.reopen_count, 1)
        self.assertFalse(tc.finance_approved)

    def test_29_pod_type_guard_and_admin_never_owner(self):
        case, slip, tc = self._authorized()
        with self.assertRaises(ValidationError):
            tc.with_user(self.delivery).write({"delivery_receipt": PDF, "delivery_receipt_name": "pod.exe"})
        admin = self.env.ref("base.user_admin")
        self.assertNotIn(admin, tc.docs_owner_id | tc.customs_owner_id | tc.delivery_owner_id | tc.current_owner_id)
PYEOF

# =============================================================================
step "4) پچ افزایشی و idempotent فایل‌های مشترک itr_transport (C2)"
# =============================================================================
python3 - "${TRN_DIR}" <<'PYEOF'
# -*- coding: utf-8 -*-
import io
import os
import sys

mod_dir = sys.argv[1]
changed = []


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


path = os.path.join(mod_dir, "models", "__init__.py")
text = read(path)
for imp in (
    "from . import itr_charge_type",
    "from . import itr_document_type",
    "from . import itr_cost_line",
    "from . import itr_payment_request",
    "from . import itr_payment_execution",
    "from . import itr_driver_coordination_log",
    "from . import money_engine",
    "from . import itr_transport_case_ops",
    "from . import itr_factory_shortfall_ops",
    "from . import itr_trade_case_transport",
):
    if imp not in text.splitlines():
        text = text.rstrip("\n") + "\n" + imp + "\n"
        changed.append("models/__init__.py + %s" % imp)
write(path, text)

path = os.path.join(mod_dir, "tests", "__init__.py")
text = read(path)
imp = "from . import test_transport_ops_phase6"
if imp not in text:
    text = text.rstrip("\n") + "\n" + imp + "\n"
    changed.append("tests/__init__.py + %s" % imp)
write(path, text)

path = os.path.join(mod_dir, "__manifest__.py")
text = read(path)
anchor = '"views/itr_transport_menus.xml",'
if anchor not in text:
    print("FATAL: manifest anchor not found - phase 5 contract changed", file=sys.stderr)
    sys.exit(2)
indent = "        "
entries = [
    '"security/itr_transport_phase6_rules.xml",',
    '"data/itr_transport_phase6_data.xml",',
    '"data/itr_transport_phase6_events.xml",',
    '"views/itr_transport_case_ops_views.xml",',
    '"views/itr_transport_phase6_views.xml",',
    '"views/itr_transport_phase6_menus.xml",',
]
last = anchor
for entry in entries:
    if entry not in text:
        text = text.replace(indent + last, indent + last + "\n" + indent + entry)
        changed.append("manifest + %s" % entry)
    last = entry
if '"version": "19.0.1.0.0",' in text:
    text = text.replace('"version": "19.0.1.0.0",', '"version": "19.0.1.1.0",')
    changed.append("manifest version -> 19.0.1.1.0")
write(path, text)
for entry in entries:
    if entry not in text:
        print("FATAL: manifest patch failed for %s" % entry, file=sys.stderr)
        sys.exit(2)

path = os.path.join(mod_dir, "security", "ir.model.access.csv")
text = read(path)
acl_lines = [
    # charge types (master: config by supervisors / finance; read by all)
    "access_itr_charge_type_user,itr.charge.type user,model_itr_charge_type,base.group_user,1,0,0,0",
    "access_itr_charge_type_trn_sup,itr.charge.type trn sup,model_itr_charge_type,itr_core.group_transport_supervisor,1,1,1,1",
    "access_itr_charge_type_fin_sup,itr.charge.type fin sup,model_itr_charge_type,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_charge_type_fin_mgr,itr.charge.type fin mgr,model_itr_charge_type,itr_core.group_financial_manager,1,1,1,1",
    "access_itr_charge_type_ceo,itr.charge.type ceo,model_itr_charge_type,itr_core.group_ceo,1,1,1,1",
    # document types
    "access_itr_document_type_user,itr.document.type user,model_itr_document_type,base.group_user,1,0,0,0",
    "access_itr_document_type_trn_sup,itr.document.type trn sup,model_itr_document_type,itr_core.group_transport_supervisor,1,1,1,1",
    "access_itr_document_type_fin_sup,itr.document.type fin sup,model_itr_document_type,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_document_type_ceo,itr.document.type ceo,model_itr_document_type,itr_core.group_ceo,1,1,1,1",
    # transport documents
    "access_itr_transport_document_user,itr.transport.document user,model_itr_transport_document,base.group_user,1,0,0,0",
    "access_itr_transport_document_docs,itr.transport.document docs,model_itr_transport_document,itr_core.group_transport_docs,1,1,1,0",
    "access_itr_transport_document_customs,itr.transport.document customs,model_itr_transport_document,itr_core.group_customs_officer,1,1,1,0",
    "access_itr_transport_document_delivery,itr.transport.document delivery,model_itr_transport_document,itr_core.group_transport_delivery,1,1,1,0",
    "access_itr_transport_document_trn_sup,itr.transport.document trn sup,model_itr_transport_document,itr_core.group_transport_supervisor,1,1,1,0",
    "access_itr_transport_document_fin_sup,itr.transport.document fin sup,model_itr_transport_document,itr_core.group_finance_supervisor,1,1,1,0",
    "access_itr_transport_document_ceo,itr.transport.document ceo,model_itr_transport_document,itr_core.group_ceo,1,1,1,0",
    # cost lines
    "access_itr_cost_line_user,itr.cost.line user,model_itr_cost_line,base.group_user,1,0,0,0",
    "access_itr_cost_line_docs,itr.cost.line docs,model_itr_cost_line,itr_core.group_transport_docs,1,1,1,0",
    "access_itr_cost_line_customs,itr.cost.line customs,model_itr_cost_line,itr_core.group_customs_officer,1,1,1,0",
    "access_itr_cost_line_delivery,itr.cost.line delivery,model_itr_cost_line,itr_core.group_transport_delivery,1,1,1,0",
    "access_itr_cost_line_trn_sup,itr.cost.line trn sup,model_itr_cost_line,itr_core.group_transport_supervisor,1,1,1,1",
    "access_itr_cost_line_fin_sup,itr.cost.line fin sup,model_itr_cost_line,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_cost_line_ceo,itr.cost.line ceo,model_itr_cost_line,itr_core.group_ceo,1,1,1,0",
    # payment requests (created only from cost lines; finance supervisor decides)
    "access_itr_payment_request_user,itr.payment.request user,model_itr_payment_request,base.group_user,1,0,0,0",
    "access_itr_payment_request_docs,itr.payment.request docs,model_itr_payment_request,itr_core.group_transport_docs,1,1,1,0",
    "access_itr_payment_request_customs,itr.payment.request customs,model_itr_payment_request,itr_core.group_customs_officer,1,1,1,0",
    "access_itr_payment_request_delivery,itr.payment.request delivery,model_itr_payment_request,itr_core.group_transport_delivery,1,1,1,0",
    "access_itr_payment_request_trn_sup,itr.payment.request trn sup,model_itr_payment_request,itr_core.group_transport_supervisor,1,1,1,0",
    "access_itr_payment_request_fin_sup,itr.payment.request fin sup,model_itr_payment_request,itr_core.group_finance_supervisor,1,1,1,0",
    "access_itr_payment_request_fin_mgr,itr.payment.request fin mgr,model_itr_payment_request,itr_core.group_financial_manager,1,1,0,0",
    "access_itr_payment_request_ceo,itr.payment.request ceo,model_itr_payment_request,itr_core.group_ceo,1,1,1,0",
    # payment executions (L2 / FIN-029: only the finance supervisor writes)
    "access_itr_payment_execution_user,itr.payment.execution user read,model_itr_payment_execution,base.group_user,1,0,0,0",
    "access_itr_payment_execution_fin_sup,itr.payment.execution fin sup,model_itr_payment_execution,itr_core.group_finance_supervisor,1,1,1,0",
    # driver coordination log
    "access_itr_driver_coordination_log_user,itr.driver.coordination.log user,model_itr_driver_coordination_log,base.group_user,1,0,0,0",
    "access_itr_driver_coordination_log_docs,itr.driver.coordination.log docs,model_itr_driver_coordination_log,itr_core.group_transport_docs,1,0,1,0",
    "access_itr_driver_coordination_log_customs,itr.driver.coordination.log customs,model_itr_driver_coordination_log,itr_core.group_customs_officer,1,0,1,0",
    "access_itr_driver_coordination_log_delivery,itr.driver.coordination.log delivery,model_itr_driver_coordination_log,itr_core.group_transport_delivery,1,0,1,0",
    "access_itr_driver_coordination_log_trn_sup,itr.driver.coordination.log trn sup,model_itr_driver_coordination_log,itr_core.group_transport_supervisor,1,0,1,0",
    # shortfall settlements + supervisor create on the phase-4 shortfall (manual close path)
    "access_itr_factory_shortfall_settlement_user,itr.factory.shortfall.settlement user,model_itr_factory_shortfall_settlement,base.group_user,1,0,0,0",
    "access_itr_factory_shortfall_settlement_fin_sup,itr.factory.shortfall.settlement fin sup,model_itr_factory_shortfall_settlement,itr_core.group_finance_supervisor,1,0,1,0",
    "access_itr_factory_shortfall_settlement_fin_mgr,itr.factory.shortfall.settlement fin mgr,model_itr_factory_shortfall_settlement,itr_core.group_financial_manager,1,0,1,0",
    "access_itr_factory_shortfall_settlement_ceo,itr.factory.shortfall.settlement ceo,model_itr_factory_shortfall_settlement,itr_core.group_ceo,1,0,1,0",
    "access_itr_factory_shortfall_trn_sup_p6,itr.factory.shortfall trn sup (manual close),itr_core.model_itr_factory_shortfall,itr_core.group_transport_supervisor,1,1,1,0",
]
for line in acl_lines:
    acl_id = line.split(",", 1)[0]
    if acl_id + "," not in text:
        text = text.rstrip("\n") + "\n" + line + "\n"
        changed.append("acl + %s" % acl_id)
write(path, text)

path = os.path.join(mod_dir, "i18n", "fa_IR.po")
text = read(path)
MARK = "#### itr_transport phase-6 translations ####"
if MARK not in text:
    text = text.rstrip("\n") + "\n\n" + MARK + """

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_charge_type
msgid "Transport Charge Type"
msgstr "نوع هزینهٔ حمل"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_cost_line
msgid "Transport Cost Line"
msgstr "ردیف هزینهٔ پروندهٔ حمل"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_payment_request
msgid "Payment Request"
msgstr "درخواست پرداخت"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_payment_execution
msgid "Payment Execution"
msgstr "اجرای قطعی پرداخت"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_document_type
msgid "Document Type"
msgstr "نوع سند"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_transport_document
msgid "Transport Case Document"
msgstr "سند پیوست پروندهٔ حمل"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_driver_coordination_log
msgid "Driver Coordination Log"
msgstr "لاگ هماهنگی راننده"

#. module: itr_transport
#: model:ir.model,name:itr_transport.model_itr_factory_shortfall_settlement
msgid "Factory Shortfall Settlement"
msgstr "تسویهٔ طلب از کارخانه"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_advance_freight
msgid "Advance freight"
msgstr "پیش‌کرایه"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_final_freight
msgid "Final freight settlement"
msgstr "صافی کرایه"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_customs_duty
msgid "Customs duty"
msgstr "عوارض گمرک"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_clearance_fee
msgid "Clearance fee"
msgstr "حق‌العمل ترخیص"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_cargo_insurance
msgid "Cargo insurance"
msgstr "بیمهٔ بار"

#. module: itr_transport
#: model:itr.charge.type,name:itr_transport.charge_other
msgid "Other cost"
msgstr "سایر هزینه‌ها"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_charge_type__category__customs
msgid "Customs duty (government)"
msgstr "عوارض گمرک (نهاد دولتی)"

#. module: itr_transport
#: model:ir.model.fields.selection,name:itr_transport.selection__itr_charge_type__category__clearance
msgid "Clearance fee (broker / border agent)"
msgstr "حق‌العمل ترخیص (ترخیص‌کار / نمایندهٔ مرز)"

#. module: itr_transport
#: code:addons/itr_transport/models/itr_payment_request.py:0
#, python-format
msgid "Duplicate payment request (key A: waybill / payee / charge type / installment)."
msgstr "پرداخت تکراری است."

#. module: itr_transport
#: model:ir.model.constraint,message:itr_transport.constraint_itr_payment_execution__execution_id_uniq
msgid "Duplicate payment execution (key B: execution id)."
msgstr "اجرای پرداخت تکراری است (کلید B: شناسهٔ اجرا)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_cost_line.py:0
#, python-format
msgid "The final freight settlement of loading %(n)s is locked until the buyer's delivery receipt (POD) is uploaded (G08 / lock L1)."
msgstr "درخواست صافی کرایهٔ بارگیری %(n)s تا بارگذاری رسید تخلیهٔ خریدار (POD) مسدود است (G08 / قفل L1)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_cost_line.py:0
#, python-format
msgid "The freight cost lines (%(t)s IRR) exceed the waybill freight anchor (%(a)s IRR) of loading %(n)s (FIN-002). The waybill only sets the ceiling."
msgstr "جمع ردیف‌های کرایه (%(t)s ریال) از سقف کرایهٔ بارنامه (%(a)s ریال) بارگیری %(n)s بیشتر است (FIN-002). بارنامه فقط سقف را تعیین می‌کند."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "The gross weight (%(g)s t) must be greater than the tare weight (%(t)s t); a negative or zero net weight is refused (OPS-022)."
msgstr "وزن پر (%(g)s تن) باید از وزن خالی (%(t)s تن) بیشتر باشد؛ وزن خالص صفر یا منفی پذیرفته نمی‌شود (OPS-022)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "A bijak is required: upload BOTH the customs declaration and the bijak before confirming (OPS-024)."
msgstr "بیجک لازم است: پیش از تأیید، هر دو فایل اظهار گمرکی و بیجک را بارگذاری کنید (OPS-024)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "Closing is blocked: %(k)s of 10 checklist items are missing on %(n)s: %(m)s (BR-102)."
msgstr "بستن مسدود است: %(k)s مورد از ۱۰ مورد چک‌لیست بارگیری %(n)s ناقص است: %(m)s (BR-102)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "A manual close requires a mandatory free-text reason (BR-112)."
msgstr "بستن دستی نیازمند ثبت دلیل اجباری متن‌آزاد است (BR-112)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "Field '%(f)s' belongs to the '%(t)s' tab; your role may not edit it (SRS 4-3 / G14 / OPS-003)."
msgstr "فیلد «%(f)s» متعلق به تب «%(t)s» است؛ نقش شما مجاز به ویرایش آن نیست (بخش ۴-۳ / G14 / OPS-003)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_transport_case_ops.py:0
#, python-format
msgid "Waybill %(w)s of issuer '%(i)s' already exists on loading %(n)s (OPS-021). Open that loading to see its history."
msgstr "بارنامهٔ %(w)s صادرکنندهٔ «%(i)s» قبلاً روی بارگیری %(n)s ثبت شده است (OPS-021). برای مشاهدهٔ سوابق آن بارگیری را باز کنید."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_payment_request.py:0
#, python-format
msgid "Only the finance supervisor may %(a)s a payment (lock L2 / FIN-029)."
msgstr "فقط سرپرست مالی می‌تواند پرداخت را %(a)s کند (قفل L2 / FIN-029)."

#. module: itr_transport
#: code:addons/itr_transport/models/itr_payment_execution.py:0
#, python-format
msgid "Payment executions are never deleted; record a reversal instead (FIN-031)."
msgstr "اجرای پرداخت هرگز حذف نمی‌شود؛ به‌جای آن رکورد معکوس ثبت کنید (FIN-031)."
"""
    changed.append("i18n/fa_IR.po + phase-6 block")
write(path, text)

print("PATCH_RESULT changed=%d" % len(changed))
for item in changed:
    print(" - " + item)
PYEOF
PATCH_RC=$?
[[ ${PATCH_RC} -eq 0 ]] || err "پچ افزایشی فایل‌های مشترک شکست خورد — هیچ نصبی انجام نمی‌شود (rollback: ${P6_BACKUP_DIR}/${TS})"
cp -f "${TRN_DIR}/i18n/fa_IR.po" "${TRN_DIR}/i18n/fa.po"
gate "G6-04" "پچ افزایشی idempotent فایل‌های مشترک فاز ۵ بدون بازنویسی (C2)" "PASS" "backup=${P6_BACKUP_DIR}/${TS}"

# =============================================================================
step "5) verify مستقل فاز ۶ (ops/verify/verify_phase6.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase6.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Independent verify of Phase 6 (V6-01 .. V6-12) - odoo shell, real users,
rolled back at the end (ADR-005 / Q15 / G01)."""
import base64
import sys
import traceback

from odoo.exceptions import AccessError, UserError, ValidationError

passed = 0
failed = 0
checks = []
PDF = base64.b64encode(b"%PDF-1.4 TEST")


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
    env = env(context=dict(env.context, itr_notify_sync=True))  # noqa: F821
    Users = env["res.users"]

    def real(login):
        user = Users.search([("login", "=", login)], limit=1)
        assert user, "seeded user missing: %s" % login
        return user

    ceo = real("hadi.karamian@irbco.local")
    fin_user = real("faezeh.heydari@irbco.local")
    fin_sup = real("ehsan.nahalparvar@irbco.local")
    fin_mgr = real("fin.mgr@irbco.local")
    legal = real("pouya.soleimani@irbco.local")
    treasury = real("atieh.alaei@irbco.local")
    receivables = real("zahra.mirzaei@irbco.local")
    trn_sup = real("najmeh.afrashtehpour@irbco.local")
    docs = real("mohaddeseh.enayati@irbco.local")
    customs = real("mohammadi@irbco.local")
    delivery = real("amini@irbco.local")

    buyer = env["res.partner"].sudo().create({"name": "TEST v6 buyer", "is_company": True})
    factory = env["res.partner"].sudo().create({"name": "TEST v6 factory", "is_company": True, "is_factory": True})
    carrier = env["res.partner"].sudo().create({"name": "TEST v6 carrier", "is_company": True, "is_shipping_line": True})
    broker = env["res.partner"].sudo().create({"name": "TEST v6 broker", "is_company": True, "is_customs_agent": True})
    charge = {c.code: c for c in env["itr.charge.type"].search([])}
    counter = {"n": 0}

    def loading(tonnage=100.0):
        case = env["itr.trade.case"].with_user(fin_user).create({
            "requested_by": ceo.id, "deal_pattern": "buy_first", "factory_id": factory.id,
            "item_ids": [(0, 0, {"name": "TEST v6 coil", "row_kind": "both", "contract_tonnage": tonnage,
                                 "purchase_price_unit": 100.0, "sale_price_unit": 120.0})]})
        case.with_user(fin_user).action_submit()
        case.with_user(legal).action_legal_approve()
        case.with_user(treasury).action_treasury_approve()
        case.with_user(receivables).action_receivables_approve()
        case.with_context(itr_trade_state_engine=True).write({"signed_document": PDF, "signed_document_filename": "s.pdf"})
        case.with_user(fin_sup).action_confirm_signed()
        slip = env["itr.sales.slip"].with_user(fin_user).create({
            "case_id": case.id, "customer_id": buyer.id,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id, "allocated_tonnage": tonnage})]})
        slip.with_user(fin_user).action_issue()
        slip.with_user(fin_user).action_hand_over_to_transport()
        tc = slip.transport_case_ids[:1]
        tc.with_user(receivables).write({"buyer_credit_confirmed": True})
        tc.with_user(trn_sup).action_authorize_loading()
        return case, slip, tc

    def waybill(tc, number):
        counter["n"] += 1
        driver = env["itr.driver"].with_user(docs).create({"name": "TEST v6 driver %s" % counter["n"], "nationality": "iranian",
                                                          "national_id": "0084575948", "mobile": "09123456789"})
        vehicle = env["itr.vehicle"].with_user(docs).create({"plate_number": "12 \u0628 %03d \u0627\u06cc\u0631\u0627\u0646 67" % (200 + counter["n"]), "plate_type": "iranian"})
        tc.with_user(docs).write({"driver_id": driver.id, "vehicle_id": vehicle.id, "carrier_id": carrier.id,
                                  "waybill_issuer": "TEST v6", "waybill_number": number, "waybill_tonnage": 100.0,
                                  "waybill_total_freight": 50_000_000.0, "insurance_amount": 1_000_000.0,
                                  "insurance_confirmed": True, "letter_match_confirmed": True})

    def to_payment(tc, number, net=96.0):
        waybill(tc, number)
        tc.with_user(docs).action_mark_loaded()
        tc.with_user(docs).action_depart()
        tc.with_user(docs).write({"gross_weight": net + 25.0, "tare_weight": 25.0})
        tc.with_user(docs).action_record_weighbridge()
        tc.with_user(customs).write({"needs_bijak": "yes", "driver_confirmed": True})
        tc.with_user(customs).action_confirm_weighbridge()
        tc.with_user(customs).write({"declaration_file": PDF, "declaration_file_name": "d.pdf", "bijak_file": PDF, "bijak_file_name": "b.pdf"})
        tc.with_user(customs).action_confirm_bijak()
        tc.with_user(customs).write({"customs_broker_id": broker.id, "clearance_status": "cleared"})
        tc.with_user(customs).action_confirm_clearance()

    def cost(tc, code, amount, user, payee, installment=1):
        return env["itr.cost.line"].with_user(user).create({"transport_case_id": tc.id, "charge_type_id": charge[code].id,
                                                           "amount": amount, "payee_name": payee, "installment_no": installment})

    def pay(line, user):
        request = line.with_user(user).action_request_payment()
        return request, request.with_user(fin_sup).action_execute(bank_reference="TEST")

    # V6-01 parallel tabs
    case, slip, tc = loading()
    waybill(tc, "V6-WB-1")
    tc.with_user(customs).write({"needs_bijak": "no", "driver_confirmed": True})
    tc.with_user(delivery).write({"payee_sheba": "IR930150000001351800087201"})
    cross = False
    try:
        tc.with_user(docs).write({"needs_bijak": "yes"})
    except UserError:
        cross = True
    chk("V6-01", "سه کارشناس روی سه تب یک پرونده بدون Lost Update؛ نوشتن بین‌تبی رد شد (6.2/G14)",
        tc.waybill_number == "V6-WB-1" and tc.needs_bijak == "no" and tc.payee_sheba_masked == "IR93****7201" and cross
        and bool(tc.docs_owner_id and tc.customs_owner_id and tc.delivery_owner_id))

    # V6-02 duplicate waybill
    case2, slip2, tc2 = loading()
    dup = False
    try:
        waybill(tc2, "V6-WB-1")
    except ValidationError:
        dup = True
    env.cr.execute("SELECT count(*) FROM pg_indexes WHERE indexname='itr_transport_case_waybill_uniq'")
    idx = env.cr.fetchone()[0]
    chk("V6-02", "بارنامهٔ تکراری رد شد + UNIQUE واقعی در pg_indexes (OPS-021)", dup and idx == 1)

    # V6-03 weights + bijak guards
    to_payment(tc2, "V6-WB-2")
    bad_weight = False
    try:
        tc2.with_user(docs).write({"gross_weight": 10.0, "tare_weight": 20.0})
    except ValidationError:
        bad_weight = True
    case3, slip3, tc3 = loading()
    waybill(tc3, "V6-WB-3")
    tc3.with_user(docs).action_mark_loaded()
    tc3.with_user(docs).write({"gross_weight": 120.0, "tare_weight": 25.0})
    tc3.with_user(docs).action_record_weighbridge()
    tc3.with_user(customs).write({"needs_bijak": "yes"})
    tc3.with_user(customs).action_confirm_weighbridge()
    no_files = False
    try:
        tc3.with_user(customs).action_confirm_bijak()
    except UserError:
        no_files = True
    chk("V6-03", "وزن پر<خالی رد شد؛ بیجک لازم بدون فایل مسدود شد (6.5/6.6)", bad_weight and no_files
        and abs(tc3.effective_tonnage - 95.0) < 1e-6 and abs(case3.item_ids[0].effective_tonnage - 95.0) < 1e-6)

    # V6-04 full payment cycle
    adv = cost(tc2, "advance_freight", 20_000_000.0, delivery, "TEST driver")
    pay(adv, delivery)
    cus = cost(tc2, "customs_duty", 3_000_000.0, customs, "TEST customs")
    cle = cost(tc2, "clearance_fee", 1_500_000.0, customs, "TEST broker")
    pay(cus, customs)
    pay(cle, customs)
    fin_line = cost(tc2, "final_freight", 30_000_000.0, delivery, "TEST driver")
    locked = False
    try:
        fin_line.with_user(delivery).action_request_payment()
    except UserError:
        locked = True
    tc2.with_user(delivery).write({"delivery_receipt": PDF, "delivery_receipt_name": "pod.pdf"})
    pay(fin_line, delivery)
    chk("V6-04", "چرخهٔ سه‌مرحله‌ای کامل؛ گمرک و ترخیص دو ردیف؛ صافی تا POD قفل (G05/G08/FIN-021)",
        locked and tc2.state == "delivered" and abs(tc2.freight_settled_base - 50_000_000.0) < 1
        and cus.category == "customs" and cle.category == "clearance" and tc2.chk_payments,
        "settled=%s due=%s" % (tc2.total_settled, tc2.final_freight_due))

    # V6-05 key A duplicate
    d1 = cost(tc2, "other_cost", 100_000.0, delivery, "TEST other")
    d2 = cost(tc2, "other_cost", 100_000.0, delivery, "TEST other")
    d1.with_user(delivery).action_request_payment()
    key_a = False
    try:
        d2.with_user(delivery).action_request_payment()
    except ValidationError:
        key_a = True
    env.cr.execute("SELECT count(*) FROM pg_indexes WHERE indexname='itr_payment_request_key_a_uniq'")
    key_a_idx = env.cr.fetchone()[0]
    chk("V6-05", "پرداخت تکراری (کلید A) رد شد + ایندکس یکتای واقعی (FIN-023/027)", key_a and key_a_idx == 1)

    # V6-06 key B + reversal
    env.cr.execute("SELECT count(*) FROM pg_indexes WHERE tablename='itr_payment_execution' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%execution_id%'")
    key_b_idx = env.cr.fetchone()[0]
    request = d1.payment_request_id
    execution = request.with_user(fin_sup).action_execute()
    double = False
    try:
        request.with_user(fin_sup).action_execute()
    except UserError:
        double = True
    no_delete = False
    try:
        execution.with_user(fin_sup).unlink()
    except UserError:
        no_delete = True
    reversal = execution.with_user(fin_sup).action_reverse(reason="TEST v6 reversal")
    chk("V6-06", "کلید B یکتا؛ اجرای مضاعف رد؛ ابطال فقط با رکورد معکوس (FIN-024/031)",
        key_b_idx >= 1 and double and no_delete and reversal.is_reversal and request.state == "requested")

    # V6-07 close 9/10 impossible
    tc2.with_user(delivery).write({"docs_final_confirmed": True})
    tc2.with_user(fin_sup).write({"finance_settled": True, "chk_purchase": True, "chk_sales": True, "finance_approved": True})
    nine = False
    try:
        tc2.with_user(fin_sup).action_close()   # d1 requested again after reversal -> chk_payments False
    except UserError:
        nine = True
    request.with_user(fin_sup).action_execute()
    d2.with_user(delivery).write({"installment_no": 2})
    pay(d2, delivery)
    tc2.with_user(delivery).action_settle()
    tc2.with_user(fin_sup).action_close()
    chk("V6-07", "بستن با ۹ از ۱۰ ناممکن؛ با ۱۰/۱۰ بسته شد؛ L4 دو پرچم (BR-101/102)", nine and tc2.state == "closed")

    # V6-08 finance flags / execution by transport user
    f1 = f2 = f3 = False
    try:
        tc3.with_user(docs).write({"finance_approved": True})
    except UserError:
        f1 = True
    try:
        tc3.sudo().write({"finance_approved": True})
    except UserError:
        f2 = True
    try:
        env["itr.payment.execution"].with_user(delivery).create({"payment_request_id": request.id, "amount": 1.0, "currency_id": env.company.currency_id.id})
    except (AccessError, UserError):
        f3 = True
    chk("V6-08", "کارشناس حمل نمی‌تواند finance_approved/پرداخت‌شده را بزند (L2/FIN-029)", f1 and f2 and f3)

    # V6-09 shortfall + partial settlement
    case4, slip4, tc4 = loading(100.0)
    to_payment(tc4, "V6-WB-4", net=96.0)
    a4 = cost(tc4, "advance_freight", 50_000_000.0, delivery, "TEST driver 4")
    pay(a4, delivery)
    tc4.with_user(delivery).write({"delivery_receipt": PDF, "delivery_receipt_name": "pod.pdf"})
    tc4.with_user(trn_sup).write({"no_more_dispatch_planned": True})
    tc4.with_user(fin_sup).write({"finance_approved": True})
    tc4.with_user(fin_sup).action_manual_close(reason="TEST v6 shortage 4 t")
    shortfall = env["itr.factory.shortfall"].search([("trade_case_item_id", "=", case4.item_ids[0].id)])
    Settlement = env["itr.factory.shortfall.settlement"].with_user(fin_sup)
    Settlement.create({"shortfall_id": shortfall.id, "settled_tonnage": 1.5})
    partial = shortfall.state
    Settlement.create({"shortfall_id": shortfall.id, "settled_tonnage": 2.5, "compensation_case_id": case4.id})
    chk("V6-09", "کسری ۴ تن ⇒ بستن دستی با دلیل ⇒ ردیف دفتر طلب ⇒ تسویهٔ جزئی و کامل (BR-111/121/122)",
        len(shortfall) == 1 and abs(shortfall.shortfall_tonnage - 4.0) < 1e-6 and partial == "partially_settled" and shortfall.state == "settled")

    # V6-10 trade case financial close
    case2.invalidate_recordset()
    case2.with_user(fin_sup).action_close_case()
    chk("V6-10", "بستن مالی پروندهٔ بازرگانی پس از بسته‌شدن همهٔ بارگیری‌ها (slips_issued→closed)", case2.state == "closed")

    # V6-11 reopen BR-123
    r_ok = r_bad = False
    try:
        tc2.with_user(fin_sup).action_reopen(reason="TEST")
    except UserError:
        r_bad = True
    tc2.with_user(fin_mgr).action_reopen(reason="TEST v6 reopen")
    r_ok = tc2.state == "delivered" and tc2.reopen_count == 1
    chk("V6-11", "بازگشایی پروندهٔ بسته فقط با گروه خاص + دلیل + نسخه (BR-123)", r_ok and r_bad)

    # V6-12 gap fills: document types, borders, SLA policies, no double engine
    doc_types = env["itr.document.type"].search_count([])
    borders = env["itr.border"].search_count([("code", "in", ("SHALAMCHEH", "PARVIZKHAN"))])
    policies = env["itr.sla.policy"].search_count([("policy_key", "like", "transport.%")])
    watches = env["itr.sla.watch"].search_count([("res_model", "=", "itr.transport.case")])
    chk("V6-12", "گپ‌های SRS پر شد: ۱۱ نوع سند (DM-108)، دو مرز غایب (DM-101)، ۶ سیاست SLA روی موتور فاز ۲ (NOT-031/G18)",
        doc_types >= 11 and borders == 2 and policies == 6 and watches > 0,
        "docs=%s borders=%s policies=%s watches=%s" % (doc_types, borders, policies, watches))

except Exception as error:  # noqa: BLE001
    traceback.print_exc()
    failed += 1
    checks.append(("V6-ERR", "FAIL", "verify crashed", str(error)))

finally:
    env.cr.rollback()  # noqa: F821

print("\nITR_VERIFY_SUMMARY: passed=%d failed=%d total=%d" % (passed, failed, len(checks)))
if failed == 0:
    print("ITR_VERIFY_RESULT: PASS")
    sys.exit(0)
else:
    print("ITR_VERIFY_RESULT: FAIL")
    sys.exit(1)
PYEOF
log "ops/verify/verify_phase6.py نوشته شد"

# =============================================================================
step "6) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python3 - "$TRN_DIR" "$OPS_DIR" <<'PYEOF'
import ast, csv, io, os, sys
import xml.etree.ElementTree as ET

trn_dir, ops_dir = sys.argv[1], sys.argv[2]
errors = []
py_count = xml_count = 0
for root_dir in (trn_dir, os.path.join(ops_dir, "verify")):
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
acl = os.path.join(trn_dir, "security", "ir.model.access.csv")
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
print("checked: %d python file(s), %d xml file(s), %d acl row(s)" % (py_count, xml_count, len(rows)))
if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
SYNTAX_RC=$?
set -e
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G6-05" "نحو پایتون/XML/CSV ماژول سالم است" "PASS" "pre-install static check"
else
  gate "G6-05" "نحو پایتون/XML/CSV ماژول سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب (rollback: ${P6_BACKUP_DIR}/${TS})"
fi

# =============================================================================
step "7) ارتقای itr_transport (فاز ۶) روی ${DB_NAME} (Q01/NFR-001)"
# =============================================================================
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${TRN_MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
TRN_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${TRN_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${TRN_AFTER}" == "installed" ]]; then
  gate "G6-06" "ارتقای itr_transport (فاز ۶) بدون خطا" "PASS" "state=installed rc=0"
else
  gate "G6-06" "ارتقای itr_transport (فاز ۶) بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${TRN_AFTER} → ${INSTALL_LOG}"
  tail -n 60 "${INSTALL_LOG}"
fi

T_CHARGE="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_charge_type')")"
T_COST="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_cost_line')")"
T_REQ="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_payment_request')")"
T_EXE="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_payment_execution')")"
T_SET="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_factory_shortfall_settlement')")"
T_DOC="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_document_type')")"
SEED_CHARGES="$(q "${DB_NAME}" "SELECT count(*) FROM itr_charge_type WHERE is_seed IS TRUE")"
G05="$(q "${DB_NAME}" "SELECT count(DISTINCT category) FROM itr_charge_type WHERE category IN ('customs','clearance')")"
KEY_A="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE indexname='itr_payment_request_key_a_uniq' AND indexdef ILIKE '%UNIQUE%'")"
KEY_B="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE tablename='itr_payment_execution' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%execution_id%'")"
WB_IDX="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE indexname='itr_transport_case_waybill_uniq'")"
SLIP_FK_UNIQ="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE tablename='itr_transport_case' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%btree (sales_slip_id)%'")"
DOCS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_document_type")"
BORDERS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_border WHERE code IN ('SHALAMCHEH','PARVIZKHAN')")"
POLICIES="$(q "${DB_NAME}" "SELECT count(*) FROM itr_sla_policy WHERE policy_key LIKE 'transport.%'")"
EVENTS="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key IN ('transport.loading_authorized','shipment.driver_assigned','shipment.waybill_recorded','shipment.weighbridge_recorded','shipment.bijak_uploaded','shipment.clearance_recorded','shipment.pod_uploaded','payment.requested','payment.rejected','payment.executed','case.closed_manually','factory_debt.recorded','factory_debt.settled','trade_case.ready_to_close')")"
echo "tables: charge=${T_CHARGE} cost=${T_COST} req=${T_REQ} exe=${T_EXE} settle=${T_SET} doc=${T_DOC} | seeds=${SEED_CHARGES} g05=${G05} keyA=${KEY_A} keyB=${KEY_B} wb=${WB_IDX} slipfk=${SLIP_FK_UNIQ} docs=${DOCS} borders=${BORDERS} policies=${POLICIES} events=${EVENTS}"
if [[ "${T_CHARGE}" == "itr_charge_type" && "${T_COST}" == "itr_cost_line" && "${T_REQ}" == "itr_payment_request" \
      && "${T_EXE}" == "itr_payment_execution" && "${T_SET}" == "itr_factory_shortfall_settlement" && "${T_DOC}" == "itr_document_type" \
      && "${SEED_CHARGES}" == "6" && "${G05}" == "2" && "${DOCS}" -ge 11 && "${BORDERS}" == "2" && "${POLICIES}" == "6" && "${EVENTS}" == "14" ]]; then
  gate "G6-07" "مدل‌ها/بذرها ساخته شدند: ۶ نوع هزینه (گمرک≠ترخیص)، ۱۱ نوع سند، ۲ مرز، ۶ سیاست SLA، ۱۴ رویداد" "PASS" "all present"
else
  gate "G6-07" "مدل‌ها/بذرها ساخته شدند" "FAIL" "seeds=${SEED_CHARGES} g05=${G05} docs=${DOCS} borders=${BORDERS} policies=${POLICIES} events=${EVENTS}"
fi
if [[ "${KEY_A}" == "1" && "${KEY_B}" -ge 1 && "${WB_IDX}" == "1" && "${SLIP_FK_UNIQ:-0}" == "0" ]]; then
  gate "G6-08" "★ نمایه‌های یکتای واقعی: کلید A، کلید B، بارنامه (OPS-021)؛ رابطهٔ N:1 هنوز غیر یکتا (FIN-027/G04/6.1)" "PASS" "pg_indexes verified"
else
  gate "G6-08" "نمایه‌های یکتای واقعی کلید A/B/بارنامه (FIN-027/G04)" "FAIL" "keyA=${KEY_A} keyB=${KEY_B} wb=${WB_IDX} slipfk=${SLIP_FK_UNIQ}"
fi

# =============================================================================
step "8) تست‌های خودکار — فاز ۶ *و* بازاجرای فازهای ۳/۴/۵ (Q04 + اثبات C2)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G6-09" "تست‌های خودکار فاز ۶ + بازاجرای ۳/۴/۵ سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
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
    gate "G6-09" "تست‌های فاز ۶ (۳ مثبت + ۶ منفی + گاردها) سبز + فازهای ۳/۴/۵ دوباره سبز (C2)" "PASS" "${TEST_TOTAL} rc=0"
  else
    gate "G6-09" "تست‌های خودکار فاز ۶ + بازاجرای ۳/۴/۵ سبز هستند" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} → ${TEST_LOG}"
    grep -A 40 -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" | head -n 200 || true
  fi
fi

# =============================================================================
step "9) verify مستقل V6-01..V6-12 (بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G6-10" "verify مستقل فاز ۶ سبز است (V6-01..V6-12)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase6.py" >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G6-10" "verify مستقل فاز ۶ سبز است (V6-01..V6-12)" "PASS" "${VERIFY_LINE}"
  else
    gate "G6-10" "verify مستقل فاز ۶ سبز است (V6-01..V6-12)" "FAIL" "${VERIFY_LINE:-خروجی یافت نشد} (rc=${VERIFY_RC}) → ${VERIFY_LOG}"
    tail -n 120 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "10) گاردهای معماری فاز ۶ (G18 تک‌موتور مالی/SLA/Task + G05 + G01 + Q05 + Q03 + G07)"
# =============================================================================
PROFIT_HITS="$(grep -rnE 'estimated_profit|sales_base *-.*purchase_base' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -vE '/models/money_engine\.py' | grep -v '/itr_core/models/itr_trade_case.py' | grep -v '/itr_transport/models/itr_trade_case_transport.py' | grep -v '/tests/' | grep -v '/ops/verify/' || true)"
ENGINE_CLASSES="$(grep -rlE '_(name|inherit) = "itr\.money\.engine"' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | wc -l | tr -d ' ')"
if [[ -z "${PROFIT_HITS}" && "${ENGINE_CLASSES}" == "2" ]]; then
  gate "G6-11" "یک موتور مالی (itr.money.engine + یک _inherit)؛ هزینه از cost.line، تسویه از execution (FIN-003/005/G18)" "PASS" "money_engine.py x2 (core + inherit)"
else
  gate "G6-11" "یک موتور مالی (G18)" "FAIL" "classes=${ENGINE_CLASSES} hits=$(echo "${PROFIT_HITS}" | head -n2 | tr '\n' ' ')"
fi

SLA_HITS="$(grep -rlnE '_cron_scan_sla|def .*escalate' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v '/itr_notify/' || true)"
SLA_CALLS="$(grep -rc 'itr.sla.service' "${TRN_DIR}/models/itr_transport_case_ops.py" | tr -d ' ')"
if [[ -z "${SLA_HITS}" && "${SLA_CALLS:-0}" -ge 1 ]]; then
  gate "G6-12" "تنها موتور SLA فاز ۲ استفاده شد؛ هیچ cron/موتور SLA دوم (NOT-035/G18)" "PASS" "open/close_watch only"
else
  gate "G6-12" "تنها موتور SLA (G18)" "FAIL" "hits=${SLA_HITS:-none} calls=${SLA_CALLS}"
fi

TASK_HITS="$(grep -rnE '_name = "itr\.(task|work\.queue|todo|cartable\.item)' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
if [[ -z "${TASK_HITS}" ]]; then
  gate "G6-13" "هیچ موتور Task/صف کار دوم؛ درخواست پرداخت هم روی همان mixin کارتابل (C1/G18)" "PASS" "clean"
else
  gate "G6-13" "هیچ موتور Task دوم (G18)" "FAIL" "$(echo "${TASK_HITS}" | head -n3 | tr '\n' ' ')"
fi

REQ_IN_REPORT="$(grep -rnE "payment\.request.*(settled|total_settled)|total_settled.*payment_request" --include='*.py' "${TRN_DIR}/models/money_engine.py" 2>/dev/null || true)"
if [[ -z "${REQ_IN_REPORT}" ]] && grep -q 'payment_execution_ids' "${TRN_DIR}/models/money_engine.py"; then
  gate "G6-14" "Ledger هزینه (تعهد) و اجرای پرداخت (نقد) تفکیک‌شده؛ درخواست هرگز «تسویه» شمرده نمی‌شود (G07/FIN-028)" "PASS" "engine reads executions only"
else
  gate "G6-14" "تفکیک تعهد/نقد (G07/FIN-028)" "FAIL" "${REQ_IN_REPORT:-engine does not read executions}"
fi

SUDO_HITS="$(grep -rn --include='*.py' '\.sudo(' "${TRN_DIR}/models" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G6-15" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/SEC-018)" "PASS" "models/ تمیز"
else
  gate "G6-15" "هیچ sudo() بدون مجوز صریح (G01/SEC-018)" "FAIL" "$(echo "${SUDO_HITS}" | head -n3 | tr '\n' ' ')"
fi

NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${TRN_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${TRN_DIR}/security" "${TRN_DIR}/views" 2>/dev/null | grep -v 'fa_IR' || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G6-16" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n/data"
else
  gate "G6-16" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

ADMIN_GROUPS="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_core' WHERE u.login='admin'")"
ADMIN_OWNER="$(q "${DB_NAME}" "SELECT (SELECT count(*) FROM itr_transport_case t JOIN res_users u ON u.id IN (t.current_owner_id,t.docs_owner_id,t.customs_owner_id,t.delivery_owner_id) WHERE u.login='admin') + (SELECT count(*) FROM itr_payment_request p JOIN res_users u ON u.id=p.current_owner_id WHERE u.login='admin')")"
if [[ "${ADMIN_GROUPS}" == "0" && "${ADMIN_OWNER:-0}" == "0" ]]; then
  gate "G6-17" "Administrator بدون نقش کسب‌وکاری و بدون هیچ بارگیری/درخواست در کارتابل (Q03/UX-003)" "PASS" "0 group / 0 owned"
else
  gate "G6-17" "Administrator بدون نقش و کارتابل (Q03/UX-003)" "FAIL" "groups=${ADMIN_GROUPS} owned=${ADMIN_OWNER}"
fi

STATE_NAMES_OK=1
for s in draft pending_review loading_authorized loaded in_transit waiting_weighbridge waiting_bijak waiting_clearance waiting_payment delivered settled closed cancelled; do
  grep -q "(\"${s}\"," "${TRN_DIR}/models/itr_transport_case.py" || STATE_NAMES_OK=0
done
if [[ ${STATE_NAMES_OK} -eq 1 ]]; then
  gate "G6-18" "۱۳ نام وضعیت قفل‌شده دست‌نخورده؛ فاز ۶ فقط جدول انتقال را با _inherit گسترش داد (G10/Q11/ADR-024)" "PASS" "13 locked states"
else
  gate "G6-18" "نام وضعیت‌ها قفل (G10)" "FAIL" "names_ok=${STATE_NAMES_OK}"
fi

# =============================================================================
step "11) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_charge_type")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_document_type")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_sla_policy")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_border")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_transport'")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${TRN_MODULE}" --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_charge_type")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_document_type")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_sla_policy")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM itr_border")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_transport'")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G6-19" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "charges|docs|sla|events|borders|xmlid = ${CNT_AFTER}"
else
  gate "G6-19" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "12) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G6-20" "فاز ۶ روی محیط UAT نصب شد" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G6-20" "فاز ۶ روی محیط UAT نصب شد" "WARN" "محیط UAT یافت نشد"
else
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  UAT_FLAG="-i"; [[ "${UAT_STATE}" == "installed" ]] && UAT_FLAG="-u"
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" "${UAT_FLAG}" "${TRN_MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_AFTER="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  UAT_KEY_A="$(q "${DB_NAME_UAT}" "SELECT count(*) FROM pg_indexes WHERE indexname='itr_payment_request_key_a_uniq'")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_AFTER}" == "installed" && "${UAT_KEY_A}" == "1" ]]; then
    gate "G6-20" "فاز ۶ روی محیط UAT نصب شد (کلید A هم آنجا واقعی است)" "PASS" "${DB_NAME_UAT} state=installed"
  else
    gate "G6-20" "فاز ۶ روی محیط UAT نصب شد" "FAIL" "rc=${UAT_RC} state=${UAT_AFTER} keyA=${UAT_KEY_A} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "13) ★ پشتیبان کامل پس از فاز + آزمون بازیابی واقعی (Q10 / Gate 6 / پیوست ج)"
# =============================================================================
if [[ "${SKIP_BACKUP}" == "1" || ! -x "${OPS_DIR}/backup.sh" ]]; then
  gate "G6-21" "پشتیبان کامل پس از فاز حساس (Q10)" "FAIL" "SKIP_BACKUP=1 یا backup.sh غایب"
  gate "G6-22" "بازیابی واقعی پشتیبان روی پایگاه‌دادهٔ خالی (پیوست ج)" "FAIL" "بدون پشتیبان"
else
  mapfile -t BK2 < <(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)
  POST_DUMP="${BK2[0]:-}"; POST_FS="${BK2[1]:-}"
  if [[ -s "${POST_DUMP:-/nonexistent}" && -f "${POST_FS:-/nonexistent}" ]]; then
    gate "G6-21" "پشتیبان کامل پس از فاز حساس (Q10)" "PASS" "$(basename "${POST_DUMP}") sha256=$(sha256sum "${POST_DUMP}" | cut -c1-12)"
  else
    gate "G6-21" "پشتیبان کامل پس از فاز حساس (Q10)" "FAIL" "backup.sh خروجی معتبر نداد"
  fi
  if [[ "${SKIP_RESTORE_TEST}" == "1" ]]; then
    gate "G6-22" "بازیابی واقعی پشتیبان روی پایگاه‌دادهٔ خالی (پیوست ج)" "FAIL" "SKIP_RESTORE_TEST=1"
  elif [[ -s "${POST_DUMP:-/nonexistent}" ]]; then
    SRC_USERS="$(q "${DB_NAME}" "SELECT count(*) FROM res_users")"
    SRC_MODS="$(q "${DB_NAME}" "SELECT count(*) FROM ir_module_module WHERE state='installed'")"
    SRC_CHARGES="$(q "${DB_NAME}" "SELECT count(*) FROM itr_charge_type")"
    if DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/restore.sh" "${POST_DUMP}" "${POST_FS}" "${DB_NAME_RESTORE}" >/dev/null 2>&1; then
      R_USERS="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM res_users")"
      R_MODS="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM ir_module_module WHERE state='installed'")"
      R_CHARGES="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM itr_charge_type")"
      R_KEY_A="$(q "${DB_NAME_RESTORE}" "SELECT count(*) FROM pg_indexes WHERE indexname='itr_payment_request_key_a_uniq'")"
      if [[ "${R_USERS}" == "${SRC_USERS}" && "${R_MODS}" == "${SRC_MODS}" && "${R_CHARGES}" == "${SRC_CHARGES}" && "${R_KEY_A}" == "1" ]]; then
        gate "G6-22" "بازیابی واقعی پشتیبان روی پایگاه‌دادهٔ خالی برابر مبدأ (شامل ایندکس‌های یکتا)" "PASS" "users=${R_USERS} modules=${R_MODS} charges=${R_CHARGES} keyA=1"
      else
        gate "G6-22" "بازیابی واقعی پشتیبان روی پایگاه‌دادهٔ خالی" "FAIL" "users=${R_USERS}/${SRC_USERS} mods=${R_MODS}/${SRC_MODS} charges=${R_CHARGES}/${SRC_CHARGES} keyA=${R_KEY_A}"
      fi
      [[ "${KEEP_RESTORE_DB}" == "1" ]] || { drop_db "${DB_NAME_RESTORE}"; log "restore-test DB پاک شد"; }
    else
      gate "G6-22" "بازیابی واقعی پشتیبان روی پایگاه‌دادهٔ خالی" "FAIL" "restore.sh خطا داد"
    fi
  else
    gate "G6-22" "بازیابی واقعی پشتیبان" "FAIL" "dump پس از فاز موجود نیست"
  fi
fi

# =============================================================================
step "14) اسناد حاکمیتی: ADR-028..033 / REUSE MAP / تحویل"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-028" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-028 — گسترش پروندهٔ حمل فقط با _inherit و گارد فیلدمحور تب‌ها (فاز ۶ — C2/G14/OPS-003)
فایل فاز ۵ (models/itr_transport_case.py) دست‌نخورده است؛ همهٔ فیلدها/اکشن‌های
عملیاتی در itr_transport_case_ops.py با _inherit اضافه شده‌اند. سه تب موازی با
گارد سمت سرور «چه نقشی چه فیلدی را می‌نویسد» (FIELD_TAB/TAB_GROUPS) پیاده شده؛
هیچ صف ایستگاهی ترتیبی وجود ندارد. فقط چهار قفل مجاز SRS ۷-۴ (L1 POD، L2 مالی،
L3 چک‌لیست ۱۰/۱۰، L4 دو پرچم موازی) در کد هستند.

## ADR-029 — دو کلید ضدتکرار مستقل پرداخت (فاز ۶ — G04/FIN-023..027)
کلید A روی itr.payment.request: ایندکس یکتای جزئی واقعی PostgreSQL
(company_id, waybill_number, payee_name, charge_type_id, installment_no)
WHERE state != 'rejected' — درخواست ردشده قابل تکرار است، مبلغ و راننده هرگز
بخشی از کلید نیستند. کلید B روی itr.payment.execution: unique(execution_id)
با models.Constraint. هر دو با pg_indexes اثبات می‌شوند (G6-08). ابطال فقط با
رکورد معکوس (FIN-031).

## ADR-030 — تعهد ≠ نقد در موتور مالی واحد (فاز ۶ — G07/FIN-003/FIN-005)
itr.money.engine با _inherit گسترش یافت (transport_totals + case_totals). هزینه
فقط از itr.cost.line و تسویه فقط از itr.payment.execution (state=done، شامل
معکوس‌های منفی) خوانده می‌شود؛ درخواست پرداخت هرگز در «تسویه» شمرده نمی‌شود.
chk_payments از «تعهد در برابر تخصیص به تفکیک ارز» + صافی کرایه (FIN-021)
محاسبه می‌شود (BR-101) — یک پرداخت مثبت هرگز آن را سبز نمی‌کند.

## ADR-031 — تناژ مؤثر و دفتر طلب (فاز ۶ — OPS-023/BR-005/BR-111/BR-121)
effective_tonnage بارگیری = باسکول تأییدشده > مقدار دستی مستند > هرگز برنامه‌ای.
roll-up به ردیف کالا (effective_tonnage) با context موتور تناژ فاز ۵ و کرسر
سیستمی انجام می‌شود (مقدار اندازه‌گیری‌شده، نه تصمیم — ITR-SUDO-OK). ردیف دفتر طلب
فقط در بستن دستی با دلیل و فقط وقتی «اعزام دیگری نیست» + همهٔ رسیدهای تخلیه
ثبت شده‌اند ساخته/به‌روز می‌شود؛ کلید یکتای فاز ۴ (trade_case_item_id) حفظ است.
تسویه جزئی و مقداری با ارجاع به معاملهٔ جبرانی (BR-122)؛ append-only.

## ADR-032 — گپ‌های SRS که نقشهٔ فازی نداشت و در فاز ۶ افزایشی پر شدند (C3)
DM-108 itr.document.type + itr.transport.document | DM-101 مرزهای شلمچه و
پرویزخان (افزوده، نه جایگزین بذر فاز ۳) | OPS-025 گارد نوع/حجم آپلود (پارامتر) |
BR-123 action_reopen با گروه financial_manager/validation_override + دلیل + نسخه |
FIN-031 معکوس‌سازی | L4 دو پرچم | OPEN-01/OPEN-02 به‌صورت ir.config_parameter |
NOT-031 شش سیاست SLA (دادهٔ قابل ویرایش) روی همان موتور فاز ۲؛ open/close_watch
در گام‌های واقعی. رویدادهای گروه B/C/D که این فاز صدا می‌زند بذر شدند (ADR-020).

## ADR-033 — بستن مالی پروندهٔ بازرگانی توسط سرپرست مالی (فاز ۶)
گذار slips_issued→closed پروندهٔ بازرگانی (جدول فاز ۴) فقط با
action_close_case توسط سرپرست مالی و پس از بسته‌شدن همهٔ بارگیری‌ها انجام می‌شود؛
بستن خودکار با sudo عمداً پیاده نشد (G01). بسته‌شدن آخرین بارگیری رویداد
trade_case.ready_to_close را برای سرپرست مالی می‌فرستد.
MDEOF
log "ADR-028..033 به ARCHITECTURE_DECISIONS.md افزوده شد"
else
  warn "ADR-028 از قبل ثبت شده — بدون تغییر"
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "itr.charge.type" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## فاز ۶ — itr_transport عملیات (Q14)
| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۶ | `itr.transport.case` فاز ۵ (فقط `_inherit`) | یک مدل حمل؛ نام وضعیت‌ها قفل (ADR-024) |
| ۶ | `itr.money.engine` فاز ۴ (`_inherit`: transport_totals/case_totals) | تنها موتور مالی (FIN-005) |
| ۶ | `itr.sla.service.open_watch/close_watch` فاز ۲ + ۶ سیاست داده‌ای | تنها موتور SLA (NOT-035) |
| ۶ | `itr.notification.service.notify()` (۱۴ رویداد بذر) | تنها نقطهٔ ورود اعلان |
| ۶ | `itr.fx.service.apply_fx` برای هر ردیف هزینه/اجرا/لنگر کرایه | قفل نرخ هر رویداد (FIN-014) |
| ۶ | `itr.validation.service.check_sheba/mask_sheba` | یک سیاست شبا (VAL-004/008) |
| ۶ | `itr.cartable.mixin` فاز ۵ روی itr.payment.request | یک قرارداد کارتابل (ADR-025) |
| ۶ | `itr.factory.shortfall` فاز ۴ (`_inherit` + مدل تسویه) | کلید BR-121 حفظ؛ مدل دوم طلب ممنوع |
| ۶ | `itr.driver`/`itr.vehicle`/`itr.border`/پرچم‌های `res.partner` فاز ۳ | ناوگان/مرز/ترخیص‌کار موازی ممنوع (Q13) |

## آنچه فازهای ۷..۱۰ باید از فاز ۶ بازاستفاده کنند (ساخت دوباره = Gate قرمز)
* گزارش G07 پرداخت‌ها فقط از `itr.payment.execution` (state=done) — هرگز `.request`.
* گزارش G02/G03/G13 و داشبورد: فقط `itr.money.engine.transport_totals/case_totals`.
* «بارگیری‌های من» فاز ۸ = current_owner_id یا سه مالک تب.
* Record Rule «خودم/تیم/همه» فاز ۷ روی transport.case، cost.line، payment.request/execution.
* اعلان‌های فاز ۱۰: به xmlid های itr_transport.event_* ارجاع دهید (event_key یکتاست).
MDEOF
log "docs/REUSE_MAP.md به‌روزرسانی شد"
fi

# =============================================================================
step "15) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G6-23" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
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
    gate "G6-23" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G6-23" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "16) ثبت Git + تگ phase-6 (Q09) + اسکن رمز (Q12)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-6: transport operations (parallel tabs, waybill/weighbridge/bijak/clearance/POD, charge master + cost lines, payment request key A + execution key B, 10-item close, manual close -> shortfall + settlements, reopen, document types, SLA policies)"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-6 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-6 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G6-24" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-6}"
else
  gate "G6-24" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi
SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' | grep -v 'test_itr' | grep -v 'test_notify' | grep -v 'required_fields' | grep -v 'itr_core_users_data.xml' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G6-25" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "PASS" "clean"
else
  gate "G6-25" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 6 — گزارش پذیرش فاز ۶"
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

write_utf8 "${DOC_DIR}/PHASE6-DELIVERY.md" <<MDEOF
# تحویل فاز ۶ — عملیات حمل، هزینهٔ داینامیک، چرخهٔ پرداخت و بستن (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-6
- وضعیت Gate 6: **${GATE_STATUS}** (هشدار: ${WARNS})
- پشتیبان پیش از فاز: $(basename "${PRE_DUMP:-none}") | پس از فاز: $(basename "${POST_DUMP:-none}") | آزمون بازیابی: ${DB_NAME_RESTORE}

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 6.1 | رابطهٔ N:1 غیر یکتا دوباره از pg_indexes اثبات شد | BR-002 |
| 6.2 | سه تب موازی با گارد فیلدمحور سرور به‌ازای نقش؛ بدون صف ایستگاهی | OPS-003، G14، X15 |
| 6.3 | راننده/ناوگان از لایهٔ Guarded (پس از FIX-P3-1) + شمارندهٔ سوابق راننده/پلاک | G13، OPS-026 |
| 6.4 | بارنامه یکتا در (شرکت+صادرکننده) = ایندکس واقعی؛ بیمه + تأیید؛ لنگر کرایه؛ تطابق نامه | OPS-021، FIN-002، X11 |
| 6.5 | خالص=پر−خالی؛ پر≤خالی مسدود؛ ثبت≠تأیید؛ effective از باسکول تأییدشده | OPS-022/023 |
| 6.6 | بیجک «نیاز دارد» ⇒ اظهار+بیجک هر دو الزامی | OPS-024 |
| 6.7 | صافی کرایه تا POD در سرور مسدود (L1) | G08 |
| 6.8 | لاگ هماهنگی راننده (فقط اطلاعاتی) | OPS-005 |
| 6.9 | itr.charge.type با ۶ بذر؛ گمرک و ترخیص دو رکورد | G05، G06، G09 |
| 6.10 | itr.cost.line چهار فیلد چندارزی + payee آزاد + شبای Guarded/ماسک | G12، VAL-004/008 |
| 6.11 | roll-up سربرگ فقط‌خواندنی از موتور مالی واحد (_inherit) | FIN-005، G18 |
| 6.12 | کلید A ایندکس یکتای واقعی + «پرداخت تکراری است.» | FIN-023/027 |
| 6.13 | کلید B (UUID) + فقط سرپرست مالی + معکوس‌سازی | FIN-024/029/031، L2 |
| 6.14 | صافی = لنگر − پیش‌کرایه؛ ضدسرریز Σfreight ≤ لنگر | FIN-021/022 |
| 6.15 | چک‌لیست ۱۰موردی؛ chk_payments به تفکیک ارز؛ بدون ۱۰/۱۰ بسته نمی‌شود (L3) | BR-101/102 |
| 6.16 | بستن دستی با دلیل ⇒ ردیف دفتر طلب (کلید BR-121) + تسویهٔ جزئی | BR-111/112/121/122 |
| گپ | DM-108، DM-101 (۲ مرز)، OPS-025، BR-123، L4، OPEN-01/02 پارامتری، NOT-031 (۶ سیاست SLA) | ADR-032 |
| C1 | سه مالک تب + مالک کلی + ارجاع تب با دلیل داخل تیم؛ درخواست پرداخت روی mixin | UX-011، G15، SEC-004 |
| C2 | fingerprint ۲۶ قرارداد؛ فقط _inherit؛ پشتیبان پیش/پس + بازیابی؛ بازاجرای تست‌های ۳/۴/۵ | Q10، پیوست ج |

## ۲) Scope خارج از فاز (عمداً انجام نشد)
ماتریس نهایی Record Rule «خودم/تیم/همه» و SoD کامل (فاز ۷)، کارتابل ده‌بخشی/Home/
داشبورد ۱۸کارته (فاز ۸ — روی مالک‌ها و state های همین فاز)، ۱۵ گزارش/چاپ/اکسل
(فاز ۹ — فقط از موتور مالی و execution)، سیم‌کشی کامل کاتالوگ اعلان و پلکان SLA
(فاز ۱۰ — سیاست‌ها و رویدادهای این فاز پایه‌اند)، سپیدار (فاز ۱۱).

## ۳) فایل‌های ایجادشده (جدید) و پچ‌شده (افزایشی)
\`\`\`
[NEW] itr_transport/models/{itr_charge_type.py, itr_document_type.py, itr_cost_line.py,
      itr_payment_request.py, itr_payment_execution.py, itr_driver_coordination_log.py,
      money_engine.py, itr_transport_case_ops.py, itr_factory_shortfall_ops.py, itr_trade_case_transport.py}
[NEW] itr_transport/security/itr_transport_phase6_rules.xml
[NEW] itr_transport/data/{itr_transport_phase6_data.xml, itr_transport_phase6_events.xml}
[NEW] itr_transport/views/{itr_transport_case_ops_views.xml, itr_transport_phase6_views.xml, itr_transport_phase6_menus.xml}
[NEW] itr_transport/tests/test_transport_ops_phase6.py
[NEW] ops/verify/verify_phase6.py
[PATCH] itr_transport/__manifest__.py, models/__init__.py, tests/__init__.py, security/ir.model.access.csv, i18n/fa_IR.po+fa.po
پشتیبان فایل‌های مشترک: docs/phase6-backup/${TS}/
\`\`\`

## ۴) ماتریس دسترسی تغییرکرده (خلاصه)
| مدل | user | docs | customs | delivery | trn_sup | fin_sup | fin_mgr | ceo | auditor |
|---|---|---|---|---|---|---|---|---|---|
| itr.charge.type | r | r | r | r | rwcu | rwcu | rwcu | rwcu | r |
| itr.cost.line | r | rwc | rwc | rwc | rwcu | rwcu | r | rwc | r |
| itr.payment.request | r | rwc* | rwc* | rwc* | rwc* | rwc | r | rwc | r |
| itr.payment.execution | r | - | - | - | - | rwc | r | r | r |
| itr.transport.document | r (غیرمالی) | rwc | rwc | rwc | rwc (همه) | rwc (همه) | r (همه) | rwc | r (همه) |
| itr.factory.shortfall.settlement | r | - | - | - | - | rc | rc | rc | r |
(* ایجاد فقط از مسیر ردیف هزینه؛ گارد مدل)

## ۵) نتیجهٔ Gate
| ID | وضعیت | سنجه | توضیح |
|---|---|---|---|
${GATE_TABLE}

## ۶) لاگ‌ها
- نصب: ${INSTALL_LOG}  | تست: ${TEST_LOG} | verify: ${VERIFY_LOG} | idempotency: ${IDEMP_LOG} | UAT: ${UAT_LOG}

## ۷) Rollback آزموده‌شده
\`\`\`bash
bash ops/restore.sh ${PRE_DUMP:-<dump پیش از فاز>} ${PRE_FS:-<filestore پیش از فاز>} ${DB_NAME}
git -C ${CUSTOM_ADDONS} checkout phase-5 -- ${TRN_MODULE}
# یا فقط فایل‌های مشترک: کپی از docs/phase6-backup/${TS}/
\`\`\`

## ۸) گام بعد
Gate 6 سبز ⇒ فاز ۷ (تثبیت مجوزها، SoD، Record Rule «خودم/تیم/همه» روی
trade.case / sales.slip / transport.case / payment.request؛ پیوست‌های مالی غیرقابل‌دانلود).
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-6: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

============================================================
 script-06 (006.sh) به پایان رسید
------------------------------------------------------------
 ماژول         : itr_transport (عملیات — فقط _inherit و فایل‌های جدید)
 تب‌ها         : اسناد/ناوگان | مرز/ترخیص | تحویل/تسویه — موازی، گارد فیلدمحور
 چهار قفل      : L1 POD | L2 مالی | L3 چک‌لیست ۱۰/۱۰ | L4 دو پرچم
 هزینه         : itr.charge.type (۶ بذر، گمرک≠ترخیص) + itr.cost.line (چندارزی)
 پرداخت        : request (کلید A) → execution (کلید B) → معکوس (FIN-031)
 بستن          : ۱۰/۱۰ یا دستی با دلیل → دفتر طلب (BR-121) → تسویهٔ جزئی (BR-122)
 گپ SRS        : DM-108، DM-101، OPS-025، BR-123، L4، OPEN-01/02، NOT-031
 پشتیبان       : پیش=$(basename "${PRE_DUMP:-none}") پس=$(basename "${POST_DUMP:-none}") + بازیابی آزموده
 verify        : ${OPS_DIR}/verify/verify_phase6.py
 گزارش تحویل   : ${DOC_DIR}/PHASE6-DELIVERY.md
 Git           : HEAD=${GIT_HEAD}  tag=phase-6
 گام بعدی      : فاز ۷ (007.sh) — تثبیت مجوزها و SoD
============================================================
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 6 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۷.${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 6 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۷ آغاز نمی‌شود.${NC}\n"
  exit 1
fi
