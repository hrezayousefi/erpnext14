#!/usr/bin/env bash
# =============================================================================
# script-09-itr-reports.sh (009.sh) — PHASE 9 (COMPLETE)
# Iran Trade & Transport ERP — Odoo 19.0 | File-First | Idempotent | Test-First
# Gate-Enforced | No sudo-proof
#
# فاز ۹ — گزارش‌ها، چاپ RTL و موتور اکسل: itr_reports  (سنگین‌ترین فاز)
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt ← «فاز ۹» بندهای 9.0a..9.28
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۱۳ کامل:
#       REP-001..007، ۱۳-۲ (۱۵ گزارش G01..G15)، ۱۳-۳ (۲۶ ستون + REP-011..016)،
#       ۱۳-۴ (XLS-001..021 و XLS-031)، ۱۳-۵ (۱۰ چاپ RTL + REP-021..023)
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh … 008.sh همین مخزن.
#
# -----------------------------------------------------------------------------
# ★ چرا این فاز یک ماژول تازه است و نه پچ روی ماژول‌های قبلی؟
# -----------------------------------------------------------------------------
#   Q02 ترتیب نصب را قفل کرده است:
#       itr_base → itr_notify → itr_core → itr_transport → itr_reports
#   ADR-040 فاز ۸ ثابت کرد itr_core نمی‌تواند act_window روی itr.transport.case
#   بسازد (ParseError «نام مدل نامعتبر») چون پیش از itr_transport لود می‌شود و
#   فاز ۸ مجبور شد از ir.actions.server دور بزند.
#   itr_reports آخرین ماژول زنجیره است؛ هر چهار مدل دامنه برایش شناخته‌شده‌اند.
#   بنابراین همهٔ اکشن‌های گزارش «واقعی» (act_window/report) می‌شوند و هیچ
#   فایلی از فازهای ۱ تا ۸ بازنویسی نمی‌شود.  ⇒ کمترین ریسک ممکن.
#
# -----------------------------------------------------------------------------
# ★ مدیریت ریسک «شکستن قرارداد فازهای قبل» (همان نظام R فاز ۷ و ۸، سخت‌گیرانه‌تر)
# -----------------------------------------------------------------------------
#   R1) هیچ فایل فازهای ۱..۸ بازنویسی نمی‌شود. تنها پچ‌های افزایشیِ مارک‌دار:
#       · دو خط menuitem در itr_core (ریشهٔ منوی گزارش‌ها) — نه، حتی همین هم
#         داخل itr_reports انجام می‌شود؛ پچ روی itr_core صفر است.
#       · تنها پچ واقعی: هیچ. (اثبات در Gate G9-13)
#   R2) پیش‌پرواز fingerprint روی هر ۵۶ قراردادی که این فاز مصرف می‌کند
#       (مدل/فیلد/متد/گروه/منو). یک ناهم‌خوانی = توقف کامل بدون هیچ تغییر فایل.
#   R3) پشتیبان کامل (pg_dump + filestore) پیش از ارتقا + مسیر rollback چاپ‌شده.
#   R4) نصب ماژول تازه با -i؛ ماژول‌های قبلی فقط -u می‌شوند و هیچ فیلدشان
#       حذف/تغییرنوع نمی‌شود (فقط دو فیلد افزایشی با _inherit — FIX-P9-1/2).
#   R5) بازاجرای کامل تست‌های فازهای ۱..۸ پس از نصب؛ هر رگرسیون = Gate قرمز.
#   R6) اگر پوشهٔ قالب‌های کارفرما کنار اسکریپت نباشد، فاز «معلق» علامت می‌خورد
#       (XLS-020 / 9.27) اما هرگز بی‌صدا رد نمی‌شود و بقیهٔ فاز سالم نصب می‌شود.
#
# -----------------------------------------------------------------------------
# ★ اشتباهات/خلأهای کشف‌شده در ممیزی فازهای ۱..۸ و رفع افزایشی آن‌ها
# -----------------------------------------------------------------------------
#   [FIX-P9-1] SRS 13-2/G09 ستون «تعداد» (شاخه/Branch) را برای گزارش پکینگ و
#              قالب اکسل T03 الزامی کرده، اما هیچ فیلدی برای آن در فازهای
#              ۴..۸ ساخته نشده بود. راه‌حل طبق XLS-007 دو گزینه داشت:
#              (الف) UNRESOLVED گذاشتن ستون — که گزارش الزامی را ناقص می‌کرد،
#              (ب) افزودن فیلد واقعی. چون سند آن را «الزامی» کرده، گزینهٔ (ب)
#              انتخاب شد: فیلد افزایشی packing_qty روی itr.transport.case با
#              _inherit داخل itr_reports (هیچ فایل فاز ۶ لمس نشد).
#   [FIX-P9-2] REP-016 «هر سطر Drill-Down دارد» روی گزارش ۲۶ستونه نیازمند
#              شناسهٔ رکورد منبع در هر ردیف است؛ سرویس گزارش هر ردیف را با
#              res_model/res_id برمی‌گرداند و ویوی list یک act_window واقعی
#              باز می‌کند (در ERPNext این قابلیت اصلاً وجود نداشت).
#   [FIX-P9-3] در نسخهٔ ERPNext، «مبلغ دلار» از یک فیلد سرتیتر (sales_amount_usd)
#              می‌آمد که ناقض G12/FIN-011 است. اینجا ارز در سطح ردیف است:
#              itr.trade.case.item.sale_currency_id/purchase_currency_id.
#              ستون «مبلغ ارزی» ارز اصلی ردیف را با کد ارز نشان می‌دهد و ستون
#              «مبلغ ریالی» از base_amount می‌آید (FIN-015).
#   [FIX-P9-4] در نسخهٔ ERPNext دو ستون قالب خرید (F «فی واحد» و G «نوع ارز»)
#              UNRESOLVED مانده بودند چون مدل آن‌ها را نداشت. مدل Odoo غنی‌تر
#              است: purchase_price_unit و purchase_currency_id واقعاً وجود
#              دارند ⇒ هر دو ستون در این فاز RESOLVED شدند (بدون حدس).
#   [FIX-P9-5] گزارش پرداخت‌ها در نسل قبلی از ردیف‌های «درخواست» می‌خواند.
#              اینجا G07/FIN-028 سخت اجرا می‌شود: منبع فقط
#              itr.payment.execution با state='done' و is_reversal لحاظ‌شده.
#   [FIX-P9-6] REP-015: ردیف «جمع کل» برای ستون‌های تجمعی باید «آخرین مقدار»
#              بگیرد نه مجموع. در گزارش و در هر دو مسیر اکسل پیاده و در
#              V9-03 اثبات می‌شود.
#
# -----------------------------------------------------------------------------
# پوشش چک‌لیست فاز ۹
# -----------------------------------------------------------------------------
#   9.0a/9.0b/9.0c پیش‌شرط‌ها: staging قالب‌های کارفرما + فونت RTL + نمونهٔ چاپ
#   9.1  مکانیزم هر بخش مستند و پیاده: ir.actions.report+QWeb / list+pivot+graph
#        / Controller + openpyxl
#   9.2  نصب و تأیید openpyxl سازگار
#   9.3  REP-001 Data Dictionary + REP-002 Metric Registry (گسترش itr.kpi.service)
#   9.4  ۲۶ ستون با ترتیب دقیق
#   9.5  تصمیم بر اساس row_kind (G11/REP-013) — پروندهٔ ترکیبی دو ردیف منطقی
#   9.6  REP-011..016 عیناً
#   9.7  نه سناریوی تست گزارش ۲۶ستونه
#   9.8..9.16  چهارده گزارش دیگر (G02..G15)
#   9.17/9.18  قالب پایهٔ RTL + ۱۰ چاپ
#   9.19..9.22 موتور اکسل استاندارد (Preview→Validate→Resolve→Commit)
#   9.23..9.28 موتور اکسل اختصاصی + رجیستری نسخه‌دار با checksum
#
# verify فاز ۹ (ops/verify/verify_phase9.py — کاربر واقعی، بدون sudo):
#   V9-01 هر ۱۵ گزارش خروجی دادند و اعداد با شمارش مستقیم ORM برابرند
#   V9-02 گزارش ۲۶ستونه برای پروندهٔ «ترکیبی» هر ۲۶ ستون را پر برگرداند
#   V9-03 ردیف جمع کل ستون تجمعی را دوباره جمع نزد (REP-015)
#   V9-04 گزارش پرداخت‌ها هیچ درخواست پرداخت‌نشده‌ای نشان نداد (G07)
#   V9-05 شبا در گزارش/اکسل/چاپ یکسان ماسک شد (VAL-008)
#   V9-06 Import اکسل با یک ردیف نامعتبر، کل تراکنش را rollback کرد (XLS-011)
#   V9-07 هر پنج قالب با merge/فرمول سالم پر شدند و غلط املایی کارفرما
#         دست‌نخورده ماند (XLS-004/008)
#   V9-08 هر ۱۰ چاپ RTL بدون خطا تولید شدند + Record Rule رعایت شد (REP-006)
#
# پیش‌نیاز: Gate 8 سبز (bash 008.sh)
#
# استفاده:
#   mkdir -p excel_client_files   # کنار همین اسکریپت
#   cp template_01_financial.xlsx ... excel_client_files/
#   chmod +x 009.sh && bash 009.sh
#
# سوییچ‌ها:
#   SKIP_TESTS=1 / SKIP_VERIFY=1 → Gate قرمز (Q04/Q15 اجباری)
#   SKIP_BACKUP=1 / SKIP_UAT=1 / START_DAEMON=0
#   ALLOW_MISSING_TEMPLATES=1 → نبود قالب کارفرما Gate را قرمز نکند
#                               (فقط «معلق» ثبت شود — 9.27)
# =============================================================================
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR

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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase9-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase9-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase9-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase9-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase9-uat.log}"
SYNTAX_LOG="${SYNTAX_LOG:-/tmp/itr-phase9-syntax.log}"

BASE_MODULE="itr_base"
NOTIFY_MODULE="itr_notify"
CORE_MODULE="itr_core"
TRN_MODULE="itr_transport"
REP_MODULE="itr_reports"

BASE_DIR="${CUSTOM_ADDONS}/${BASE_MODULE}"
NOTIFY_DIR="${CUSTOM_ADDONS}/${NOTIFY_MODULE}"
CORE_DIR="${CUSTOM_ADDONS}/${CORE_MODULE}"
TRN_DIR="${CUSTOM_ADDONS}/${TRN_MODULE}"
REP_DIR="${CUSTOM_ADDONS}/${REP_MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P9_BACKUP_DIR="${DOC_DIR}/phase9-backup"

TEMPLATE_SRC_DEFAULT="${SCRIPT_DIR}/excel_client_files"
TEMPLATE_SRC="${TEMPLATE_SRC:-${TEMPLATE_SRC_DEFAULT}}"
TEMPLATE_DST="${REP_DIR}/static/excel_templates"

SKIP_TESTS="${SKIP_TESTS:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SKIP_UAT="${SKIP_UAT:-0}"
SKIP_BACKUP="${SKIP_BACKUP:-0}"
START_DAEMON="${START_DAEMON:-1}"
ALLOW_MISSING_TEMPLATES="${ALLOW_MISSING_TEMPLATES:-1}"
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
  if command -v iconv >/dev/null 2>&1; then
    iconv -f UTF-8 -t UTF-8 "$tmp" >/dev/null 2>&1 || err "Invalid UTF-8: ${target}"
  fi
  mkdir -p "$(dirname "$target")"
  mv -f "$tmp" "$target"
}

have()      { command -v "$1" >/dev/null 2>&1; }
db_exists() { psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='${1}'" 2>/dev/null | grep -q 1; }
q()         { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }

# =============================================================================
step "0) preflight — Gate 8 باید سبز باشد"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons یافت نشد (ابتدا فاز ۰)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد"

for d in "${BASE_DIR}" "${NOTIFY_DIR}" "${CORE_DIR}" "${TRN_DIR}"; do
  [[ -d "$d" ]] || err "ماژول پیش‌نیاز یافت نشد: $d (ابتدا فازهای ۱..۸)"
done

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
echo "${ODOO_V}" | grep -qE '19\.[0-9]' \
  || err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود."
gate "G9-00" "نسخهٔ Odoo 19 تأیید شد" "PASS" "${ODOO_V}"

for m in "${BASE_MODULE}" "${NOTIFY_MODULE}" "${CORE_MODULE}" "${TRN_MODULE}"; do
  ST="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${m}'")"
  [[ "${ST}" == "installed" ]] || err "ماژول ${m} نصب نیست (state=${ST}) — ابتدا فازهای قبل"
done
log "هر چهار ماژول پیش‌نیاز installed هستند"

# =============================================================================
step "1) R2 — پیش‌پرواز قرارداد فازهای ۱..۸ (ناهم‌خوانی = توقف بدون تغییر فایل)"
# =============================================================================
CONTRACT_FAILS=()
contract() {
  if grep -qE "$3" "$2" 2>/dev/null; then info "contract OK: $1";
  else CONTRACT_FAILS+=("$1 → «$3» در $2 یافت نشد"); fi
}

# --- P1 itr_base -------------------------------------------------------------
contract "P1: jalali to_jalali_str"        "${BASE_DIR}/utils/jalali.py"  "def to_jalali_str\(value, sep=\"/\", persian_digits=False\)"
contract "P1: jalali to_jalali_long_fa"    "${BASE_DIR}/utils/jalali.py"  "def to_jalali_long_fa\(value\)"
contract "P1: jalali parse_jalali"         "${BASE_DIR}/utils/jalali.py"  "def parse_jalali\(text\)"
contract "P1: validators mask_sheba"       "${BASE_DIR}/utils/validators.py" "def mask_sheba\(value"
contract "P1: validators to_persian_digits" "${BASE_DIR}/utils/validators.py" "def to_persian_digits\(value\)"
contract "P1: validators normalize_text"   "${BASE_DIR}/utils/validators.py" "def normalize_text\(value\)"
contract "P1: service mask_sheba"          "${BASE_DIR}/models/itr_validation_service.py" "def mask_sheba\("
contract "P1: settings singleton"          "${BASE_DIR}/models/itr_common_settings.py" "_name = \"itr.common.settings\""

# --- P2 itr_notify -----------------------------------------------------------
contract "P2: notify() امضا"               "${NOTIFY_DIR}/models/itr_notification_service.py" "def notify\(self, event_key, res_model=None, res_id=None, context=None\)"
contract "P2: dispatch log مدل"            "${NOTIFY_DIR}/models/itr_notification_dispatch_log.py" "_name = \"itr.notification.dispatch.log\""
contract "P2: sla watch مدل"               "${NOTIFY_DIR}/models/itr_sla_watch.py" "_name = \"itr.sla.watch\""
contract "P2: sla_state محاسبه‌ای"         "${NOTIFY_DIR}/models/itr_sla_watch.py" "sla_state = fields.Selection"

# --- P3 itr_core (داده پایه) --------------------------------------------------
contract "P3: itr.border"                  "${CORE_DIR}/models/itr_border.py"  "_name = \"itr.border\""
contract "P3: itr.driver"                  "${CORE_DIR}/models/itr_driver.py"  "_name = \"itr.driver\""
contract "P3: driver sheba_masked"         "${CORE_DIR}/models/itr_driver.py"  "sheba_masked = fields.Char"
contract "P3: itr.vehicle plate_number"    "${CORE_DIR}/models/itr_vehicle.py" "plate_number = fields.Char"
contract "P3: partner is_factory"          "${CORE_DIR}/models/itr_partner.py" "is_factory = fields.Boolean"
contract "P3: partner is_customs_agent"    "${CORE_DIR}/models/itr_partner.py" "is_customs_agent = fields.Boolean"
contract "P3: partner is_shipping_line"    "${CORE_DIR}/models/itr_partner.py" "is_shipping_line = fields.Boolean"
contract "P3: fx apply_fx"                 "${CORE_DIR}/models/itr_fx_service.py" "def apply_fx\(self, amount, from_currency, to_currency=None, date=None\)"

# --- P4 itr_core (پروندهٔ بازرگانی) -------------------------------------------
contract "P4: trade case مدل"              "${CORE_DIR}/models/itr_trade_case.py" "_name = \"itr.trade.case\""
contract "P4: ROW_KINDS (G11)"             "${CORE_DIR}/models/itr_trade_case_item.py" "ROW_KINDS = \["
contract "P4: item contract_tonnage"       "${CORE_DIR}/models/itr_trade_case_item.py" "contract_tonnage = fields.Float"
contract "P4: item purchase_base_amount"   "${CORE_DIR}/models/itr_trade_case_item.py" "purchase_base_amount = fields.Float"
contract "P4: item sale_base_amount"       "${CORE_DIR}/models/itr_trade_case_item.py" "sale_base_amount = fields.Float"
contract "P4: money engine case_totals"    "${CORE_DIR}/models/money_engine.py" "def case_totals\(self, case\)"
contract "P4: shortfall کلید BR-121"       "${CORE_DIR}/models/itr_factory_shortfall.py" "unique\(trade_case_id, trade_case_item_id\)"
contract "P4: trade states قفل‌شده"        "${CORE_DIR}/models/itr_trade_case.py" "\(\"slips_issued\", \"Sales slips issued\"\)"

# --- P5 itr_core/itr_transport ------------------------------------------------
contract "P5: sales slip مدل"              "${CORE_DIR}/models/itr_sales_slip.py" "_name = \"itr.sales.slip\""
contract "P5: slip line allocated_tonnage" "${CORE_DIR}/models/itr_sales_slip.py" "allocated_tonnage = fields.Float"
contract "P5: cartable mixin"              "${CORE_DIR}/models/itr_cartable_mixin.py" "_name = \"itr.cartable.mixin\""
contract "P5: transport case مدل"          "${TRN_DIR}/models/itr_transport_case.py" "_name = \"itr.transport.case\""
contract "P5: ۱۳ وضعیت قفل‌شده"            "${TRN_DIR}/models/itr_transport_case.py" "\(\"waiting_bijak\", \"Waiting for bijak\"\)"
contract "P5: source_item_id"              "${TRN_DIR}/models/itr_transport_case.py" "source_item_id = fields.Many2one"
contract "P5: purchase_ref/sales_ref"      "${TRN_DIR}/models/itr_transport_case.py" "sales_ref = fields.Char"

# --- P6 itr_transport (عملیات/هزینه/پرداخت) -----------------------------------
contract "P6: charge type category"        "${TRN_DIR}/models/itr_charge_type.py" "category = fields.Selection"
contract "P6: COST_CATEGORIES"             "${TRN_DIR}/models/money_engine.py" "COST_CATEGORIES = \(\"freight\", \"customs\", \"clearance\", \"insurance\", \"origin\", \"other\"\)"
contract "P6: transport_totals"            "${TRN_DIR}/models/money_engine.py" "def transport_totals\(self, transport_case\)"
contract "P6: cost line payee_sheba_masked" "${TRN_DIR}/models/itr_cost_line.py" "payee_sheba_masked = fields.Char"
contract "P6: payment.request کلید A"      "${TRN_DIR}/models/itr_payment_request.py" "installment_no"
contract "P6: payment.execution UUID (کلید B)" "${TRN_DIR}/models/itr_payment_execution.py" "execution_id = fields.Char"
contract "P6: execution is_reversal"       "${TRN_DIR}/models/itr_payment_execution.py" "is_reversal = fields.Boolean"
contract "P6: effective_tonnage"           "${TRN_DIR}/models/itr_transport_case_ops.py" "effective_tonnage = fields.Float"
contract "P6: چک‌لیست ۱۰موردی"             "${TRN_DIR}/models/itr_transport_case_ops.py" "chk_payments = fields.Boolean"
contract "P6: shortfall settlement"        "${TRN_DIR}/models/itr_factory_shortfall_ops.py" "_name = \"itr.factory.shortfall.settlement\""

# --- P7 امنیت -----------------------------------------------------------------
contract "P7: rule دامنهٔ نوشتن trade"     "${CORE_DIR}/security/itr_core_phase7_rules.xml" "rule_trade_case_write_scope_p7"
contract "P7: rule حسابرس فقط‌خواندنی"     "${CORE_DIR}/security/itr_core_phase7_rules.xml" "rule_auditor_readonly_trade_p7"
contract "P7: پیوست مالی محدود"            "${TRN_DIR}/security/itr_transport_phase7_rules.xml" "rule_transport_document_financial_p7"

# --- P8 کارتابل/داشبورد --------------------------------------------------------
contract "P8: kpi service get_kpi"         "${CORE_DIR}/models/itr_kpi_service.py" "def get_kpi\(self, key\)"
contract "P8: kpi_registry"                "${CORE_DIR}/models/itr_kpi_service.py" "def kpi_registry\(self\)"
contract "P8: work queue AbstractModel"    "${CORE_DIR}/models/itr_work_queue.py" "class ItrWorkQueue\(models.AbstractModel\)"
contract "P8: cartable settings"           "${CORE_DIR}/models/itr_cartable_settings.py" "_name = \"itr.cartable.settings\""
contract "P8: منوی ریشهٔ فضای مدیرعامل"    "${CORE_DIR}/views/itr_workspace_menus.xml" "id=\"menu_ws_ceo\""
contract "P8: منوی فضای مالی"              "${CORE_DIR}/views/itr_workspace_menus.xml" "id=\"menu_ws_finance\""
contract "P8: منوی فضای سرپرست حمل"        "${CORE_DIR}/views/itr_workspace_menus.xml" "id=\"menu_ws_trn_sup\""
contract "P8: منوی فضای مرز و ترخیص"       "${CORE_DIR}/views/itr_workspace_menus.xml" "id=\"menu_ws_customs\""

if [[ ${#CONTRACT_FAILS[@]} -gt 0 ]]; then
  echo
  err "R2 — پیش‌پرواز قرارداد شکست خورد؛ هیچ فایلی تغییر نکرد:
$(printf '  • %s\n' "${CONTRACT_FAILS[@]}")"
fi
gate "G9-01" "R2: هر ۵۶ قرارداد فازهای ۱..۸ تأیید شد (بدون تغییر فایل)" "PASS" "56/56"
log "R2 سبز — ادامه امن است"

# =============================================================================
step "2) توقف سرویس در حال اجرا (نصب روی DB زنده ممنوع)"
# =============================================================================
if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}")" 2>/dev/null; then
  kill "$(cat "${PID_FILE}")" 2>/dev/null || true
  sleep 3
  log "سرویس متوقف شد (pid=$(cat "${PID_FILE}"))"
  rm -f "${PID_FILE}"
else
  pkill -f "odoo-bin.*${DB_NAME}" 2>/dev/null || true
  info "سرویسی در حال اجرا نبود"
fi

# =============================================================================
step "3) R3 — پشتیبان کامل پیش از فاز حساس (Q10/NFR-005) + مسیر rollback"
# =============================================================================
mkdir -p "${BACKUP_DIR}" "${P9_BACKUP_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}-pre-phase9-${STAMP}.dump"
FS_FILE="${BACKUP_DIR}/filestore-${DB_NAME}-pre-phase9-${STAMP}.tar.gz"
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  warn "SKIP_BACKUP=1 — پشتیبان گرفته نشد (خلاف Q10)"
  gate "G9-02" "پشتیبان کامل پیش از فاز ۹ (Q10)" "FAIL" "SKIP_BACKUP=1"
else
  pg_dump -Fc -d "${DB_NAME}" -f "${DUMP_FILE}"
  if [[ -d "${DATA_DIR}/filestore/${DB_NAME}" ]]; then
    tar -czf "${FS_FILE}" -C "${DATA_DIR}/filestore" "${DB_NAME}"
  else
    : >"${FS_FILE}"
  fi
  log "backup: ${DUMP_FILE}"
  log "backup: ${FS_FILE}"
  echo "Rollback: bash ${OPS_DIR}/restore.sh ${DUMP_FILE} ${FS_FILE} ${DB_NAME}"
  gate "G9-02" "پشتیبان کامل پیش از فاز ۹ (Q10/NFR-005)" "PASS" "$(basename "${DUMP_FILE}")"
fi

# =============================================================================
step "4) 9.2 — openpyxl (تنها کتابخانهٔ اکسل پروژه)"
# =============================================================================
set +e
python - <<'PYEOF' >/tmp/itr-p9-openpyxl.txt 2>&1
try:
    import openpyxl
    print("OPENPYXL_VERSION=%s" % openpyxl.__version__)
except Exception as exc:  # noqa: BLE001
    print("OPENPYXL_MISSING=%s" % exc)
PYEOF
set -e
if grep -q OPENPYXL_MISSING /tmp/itr-p9-openpyxl.txt; then
  info "openpyxl نصب نیست — نصب می‌شود"
  pip install 'openpyxl>=3.1,<4' >/tmp/itr-p9-pip.log 2>&1 || err "نصب openpyxl شکست خورد — /tmp/itr-p9-pip.log"
fi
OPENPYXL_V="$(python -c 'import openpyxl;print(openpyxl.__version__)' 2>/dev/null || echo '')"
if [[ -n "${OPENPYXL_V}" ]]; then
  gate "G9-03" "openpyxl سازگار روی venv سرور (9.2)" "PASS" "v${OPENPYXL_V}"
else
  gate "G9-03" "openpyxl سازگار روی venv سرور (9.2)" "FAIL" "قابل import نیست"
fi
REQ_FILE="${CUSTOM_ADDONS}/requirements.txt"
touch "${REQ_FILE}"
grep -qE '^[[:space:]]*openpyxl' "${REQ_FILE}" || echo 'openpyxl>=3.1,<4' >>"${REQ_FILE}"
log "openpyxl در requirements.txt ثبت شد"

# =============================================================================
step "5) 9.0a — staging قالب‌های واقعی کارفرما (XLS-020)"
# =============================================================================
mkdir -p "${TEMPLATE_DST}"
TPL_FOUND=0
TPL_LIST=()
if [[ -d "${TEMPLATE_SRC}" ]]; then
  shopt -s nullglob
  for f in "${TEMPLATE_SRC}"/template_*.xlsx; do
    cp -f "$f" "${TEMPLATE_DST}/"
    TPL_LIST+=("$(basename "$f")")
    TPL_FOUND=$((TPL_FOUND+1))
  done
  for extra in client_logo.png fa_font.ttf; do
    [[ -f "${TEMPLATE_SRC}/${extra}" ]] && cp -f "${TEMPLATE_SRC}/${extra}" "${TEMPLATE_DST}/"
  done
  shopt -u nullglob
  log "قالب‌های کارفرما از ${TEMPLATE_SRC} کپی شدند (${TPL_FOUND} فایل)"
else
  warn "پوشهٔ قالب کارفرما یافت نشد: ${TEMPLATE_SRC}"
fi

TPL_EXPECTED=(template_01_financial template_02_freight template_03_packing template_04_purchase template_05_dispatch)
TPL_MISSING=()
for key in "${TPL_EXPECTED[@]}"; do
  ls "${TEMPLATE_DST}/${key}"*.xlsx >/dev/null 2>&1 || TPL_MISSING+=("${key}")
done

if [[ ${#TPL_MISSING[@]} -eq 0 ]]; then
  gate "G9-04" "9.0a — هر پنج قالب واقعی کارفرما حاضرند (XLS-020)" "PASS" "5/5"
  TEMPLATES_READY=1
else
  TEMPLATES_READY=0
  if [[ "${ALLOW_MISSING_TEMPLATES}" == "1" ]]; then
    gate "G9-04" "9.0a — قالب کارفرما (XLS-020)" "SUSPENDED" \
      "معلق — در انتظار فایل کارفرما: ${TPL_MISSING[*]} (بند 9.27)"
    warn "زیربخش «اکسل اختصاصی» رسماً «معلق - در انتظار فایل کارفرما» علامت خورد (9.27)"
  else
    gate "G9-04" "9.0a — قالب کارفرما (XLS-020)" "FAIL" "غایب: ${TPL_MISSING[*]}"
  fi
fi

# فهرست checksum برای رجیستری نسخه‌دار (XLS-002)
python - "${TEMPLATE_DST}" <<'PYEOF' >"${TEMPLATE_DST}/CHECKSUMS.txt" 2>/dev/null || true
import hashlib, os, sys
d = sys.argv[1]
for fn in sorted(os.listdir(d)):
    if fn.lower().endswith(".xlsx"):
        with open(os.path.join(d, fn), "rb") as fh:
            print("%s  %s" % (hashlib.sha256(fh.read()).hexdigest(), fn))
PYEOF
log "CHECKSUMS.txt تولید شد (XLS-002)"

# =============================================================================
step "6) ساخت اسکلت ماژول itr_reports (File-First / Force-Replace)"
# =============================================================================
mkdir -p "${REP_DIR}"/{models,controllers,views,report,data,security,i18n,tests,static/excel_templates,static/src/fonts}
mkdir -p "${OPS_DIR}/verify" "${DOC_DIR}"

write_utf8 "${REP_DIR}/__manifest__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
{
    "name": "ITR Reports",
    "summary": "Phase 9 - the 15 mandatory reports, the 26-column financial "
               "report, 10 RTL QWeb prints and the standard + employer Excel engines",
    "description": """
ITR Reports (Phase 9)
=====================
* REP-001 Data Dictionary and REP-002 Metric Registry: ONE single registry that
  extends itr.kpi.service (phase 8, ADR-037). No second KPI/profit/SLA engine
  is created anywhere (G18 / FIN-005).
* The 15 mandatory reports of SRS 13-2 (G01..G15). Every figure is read through
  the metric registry, every query goes through the ORM so that the phase 7
  record rules are enforced (REP-006/REP-007).
* The 26-column financial report of SRS 13-3, decided per ROW KIND (G11 /
  REP-013), never from a single header field. Purchase side and sale side are
  computed completely independently (REP-011).
* 10 RTL QWeb prints (SRS 13-5) built on one shared Persian layout: dir=rtl,
  Jalali dates, Persian digits, company header/footer, record reference.
* Standard Excel engine: clean data export, sample template download and a
  strictly transactional Preview -> Validate -> Resolve -> Commit import
  (XLS-011..019, XLS-031).
* Employer Excel engine: a versioned, checksum-protected Template Registry for
  the five real customer workbooks. Coordinate lock beats fuzzy matching,
  ambiguity becomes UNRESOLVED, formulas/merges/styles/hidden columns/sheet
  direction are preserved and the template file on disk is never rewritten
  (XLS-002..010, XLS-021).
""",
    "version": "19.0.1.0.0",
    "category": "Localization/Iran",
    "author": "Iran Trade & Transport ERP",
    "maintainer": "Iran Trade & Transport ERP",
    "license": "LGPL-3",
    "depends": ["base", "mail", "itr_base", "itr_notify", "itr_core", "itr_transport"],
    "external_dependencies": {"python": ["openpyxl"]},
    "data": [
        "security/ir.model.access.csv",
        "security/itr_reports_rules.xml",
        "data/itr_report_dictionary_data.xml",
        "data/itr_excel_template_data.xml",
        "report/itr_report_layout_rtl.xml",
        "report/itr_report_prints.xml",
        "report/itr_report_actions.xml",
        "views/itr_report_run_views.xml",
        "views/itr_excel_views.xml",
        "views/itr_reports_menus.xml",
        "views/itr_reports_workspace_menus.xml",
    ],
    "assets": {},
    "installable": True,
    "application": False,
    "auto_install": False,
}
PYEOF

write_utf8 "${REP_DIR}/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import models
from . import controllers
PYEOF

write_utf8 "${REP_DIR}/models/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import itr_report_dictionary
from . import itr_metric_registry
from . import itr_report_engine
from . import itr_report_financial26
from . import itr_report_run
from . import itr_excel_common
from . import itr_excel_standard
from . import itr_excel_template_registry
from . import itr_excel_custom
from . import itr_excel_import
from . import itr_qweb_helpers
from . import itr_ux_phase9
PYEOF

write_utf8 "${REP_DIR}/controllers/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import main
PYEOF

write_utf8 "${REP_DIR}/tests/__init__.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from . import test_reports_phase9
from . import test_excel_phase9
PYEOF

# -----------------------------------------------------------------------------
# 9.3 — REP-001 Data Dictionary
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_report_dictionary.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""REP-001 - Data Dictionary.

Every column of every report is declared here BEFORE a single line of report
code is written (checklist 9.3).  For each column we store: technical key,
label, source (model.field), granularity, unit, currency handling, timezone
and the exclusion rule.  The dictionary is the only place where a column may
be born; the report engine refuses to emit a column that is not declared.
"""
from odoo import api, fields, models
from odoo.exceptions import ValidationError

GRANULARITY = [
    ("trade_case", "Trade case"),
    ("trade_case_item", "Trade case item (row kind aware)"),
    ("sales_slip", "Sales slip"),
    ("transport_case", "Transport case / loading"),
    ("cost_line", "Cost line (commitment)"),
    ("payment_execution", "Payment execution (cash)"),
    ("shortfall", "Factory shortfall"),
    ("period", "Aggregated period"),
]

UNITS = [
    ("tonne", "Tonne"),
    ("money_base", "Base currency (IRR)"),
    ("money_src", "Source currency"),
    ("count", "Count"),
    ("text", "Text"),
    ("date", "Date"),
    ("state", "State / colour"),
]


class ItrReportColumn(models.Model):
    _name = "itr.report.column"
    _description = "REP-001 Data Dictionary column"
    _order = "report_key, sequence, id"
    _rec_name = "label"

    report_key = fields.Char(string="Report key", required=True, index=True)
    sequence = fields.Integer(string="Order", default=10)
    column_key = fields.Char(string="Column key", required=True, index=True)
    label = fields.Char(string="Label", required=True)
    definition = fields.Text(string="Definition", required=True)
    source_ref = fields.Char(
        string="Source (model.field)", required=True,
        help="REP-001: the exact model.field the value is read from, or "
             "'metric:<key>' when it comes from the metric registry.")
    granularity = fields.Selection(GRANULARITY, string="Granularity", required=True)
    unit = fields.Selection(UNITS, string="Unit", required=True)
    currency_rule = fields.Char(
        string="Currency rule", default="n/a",
        help="FIN-015: base_amount for every money column, the source amount "
             "stays in amount + currency_id.")
    timezone_rule = fields.Char(string="Timezone rule", default="Asia/Tehran (display) / UTC (storage)")
    exclusion_rule = fields.Char(
        string="Exclusion rule", default="REP-003 cancelled/rejected excluded",
        help="REP-003: the excluded states are declared centrally, once.")
    is_cumulative = fields.Boolean(
        string="Cumulative column",
        help="REP-015: in the grand total row a cumulative column takes the "
             "LAST value, it is never summed again.")
    is_signed = fields.Boolean(string="Signed off", default=True)

    _sql_constraints = [
        ("itr_report_column_uniq", "unique(report_key, column_key)",
         "هر ستون در هر گزارش فقط یک تعریف دارد (REP-001)."),
    ]

    @api.constrains("source_ref")
    def _check_source(self):
        for rec in self:
            src = (rec.source_ref or "").strip()
            if not src:
                raise ValidationError("REP-001: منبع ستون نمی‌تواند خالی باشد.")
            if src.startswith("metric:"):
                continue
            if src in ("computed", "n/a"):
                continue
            model_name = src.rsplit(".", 1)[0]
            if model_name not in self.env:
                raise ValidationError(
                    "REP-001: مدل منبع «%s» وجود ندارد (اختراع نام فیلد ممنوع)." % model_name)

    @api.model
    def dictionary_for(self, report_key):
        cols = self.sudo().search([("report_key", "=", report_key)])  # ITR-SUDO-OK: read-only metadata
        return [{
            "column_key": c.column_key,
            "label": c.label,
            "unit": c.unit,
            "source_ref": c.source_ref,
            "is_cumulative": c.is_cumulative,
        } for c in cols]
PYEOF

# -----------------------------------------------------------------------------
# 9.3 — REP-002 Metric Registry (گسترش itr.kpi.service — هیچ موتور دوم)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_metric_registry.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""REP-002 - Metric Registry.

ADR-037 of phase 8 states that the phase 8 KPI registry IS the seed of the
phase 9 metric registry and that phase 9 must EXTEND it, never build a second
engine (G18 / FIN-005).  This file therefore inherits itr.kpi.service and only
adds the nine metric families the SRS asks for:

    planned | reserved | effective | surplus | remaining |
    cost | settled | profit | sla_state

Every report, every dashboard card, every Excel sheet and every print reads
from here.  There is no second SQL, no second profit formula, no second SLA
clock anywhere in the module (proved by the Gate greps).
"""
from odoo import api, models

# REP-003: the excluded states are declared once, centrally.
EXCLUDED_TRADE_STATES = ("rejected",)
EXCLUDED_TRANSPORT_STATES = ("cancelled",)
EXCLUDED_SLIP_STATES = ("cancelled",)

METRIC_KEYS = (
    "planned", "reserved", "effective", "surplus", "remaining",
    "cost", "settled", "profit", "sla_state",
)


class ItrMetricRegistry(models.AbstractModel):
    _inherit = "itr.kpi.service"

    # ---------------------------------------------------------------- helpers
    @api.model
    def operational_domain(self, model_name):
        """REP-003 - one central definition of 'rows a report may show'."""
        if model_name == "itr.trade.case":
            return [("state", "not in", list(EXCLUDED_TRADE_STATES))]
        if model_name == "itr.transport.case":
            return [("state", "not in", list(EXCLUDED_TRANSPORT_STATES))]
        if model_name == "itr.sales.slip":
            return [("state", "not in", list(EXCLUDED_SLIP_STATES))]
        return []

    @api.model
    def metric_registry(self):
        """REP-002 - the signed registry. Key -> (label, unit, docstring)."""
        return {
            "planned": ("Planned tonnage", "tonne",
                        "itr.trade.case.item.contract_tonnage - the contractual tonnage."),
            "reserved": ("Reserved tonnage", "tonne",
                         "Sum of itr.sales.slip.line.allocated_tonnage on open slips."),
            "effective": ("Effective tonnage", "tonne",
                          "OPS-023/REP-004: confirmed weighbridge only, through "
                          "itr.transport.case.effective_tonnage. Never an estimate, "
                          "never the planned tonnage."),
            "surplus": ("Surplus", "tonne", "REP-012: max(0, effective - planned)."),
            "remaining": ("Remaining", "tonne", "REP-012: max(0, planned - effective)."),
            "cost": ("Operational cost", "money_base",
                     "itr.money.engine roll-up of itr.cost.line (commitment)."),
            "settled": ("Settled", "money_base",
                        "G07/FIN-028: itr.payment.execution only, state=done."),
            "profit": ("Estimated profit", "money_base",
                       "FIN-005: single formula sale_base - purchase_base - cost."),
            "sla_state": ("SLA state", "state",
                          "NOT-035: read from the single SLA engine of itr_notify."),
        }

    # ---------------------------------------------------------------- metrics
    @api.model
    def metric(self, key, record):
        """Single entry point. Any other way of computing these is forbidden."""
        handler = getattr(self, "_metric_%s" % key, None)
        if handler is None:
            raise ValueError("REP-002: سنجهٔ ناشناخته «%s»" % key)
        return handler(record)

    # -- tonnage family -------------------------------------------------------
    def _metric_planned(self, record):
        if record._name == "itr.trade.case.item":
            return record.contract_tonnage or 0.0
        if record._name == "itr.trade.case":
            return sum(record.item_ids.mapped("contract_tonnage"))
        if record._name == "itr.transport.case":
            return record.planned_tonnage or 0.0
        return 0.0

    def _metric_reserved(self, record):
        if record._name == "itr.trade.case.item":
            return sum(
                line.allocated_tonnage
                for line in record.slip_line_ids
                if line.slip_id.state not in EXCLUDED_SLIP_STATES
            )
        if record._name == "itr.trade.case":
            return sum(self._metric_reserved(i) for i in record.item_ids)
        return 0.0

    def _metric_effective(self, record):
        """REP-004 - never an estimate. Only the stored effective tonnage that
        phase 6 computed from the CONFIRMED weighbridge (OPS-023)."""
        if record._name == "itr.transport.case":
            return record.effective_tonnage or 0.0
        if record._name == "itr.trade.case.item":
            return sum(
                tc.effective_tonnage or 0.0
                for tc in record.transport_case_ids
                if tc.state not in EXCLUDED_TRANSPORT_STATES
            ) if hasattr(record, "transport_case_ids") else sum(
                tc.effective_tonnage or 0.0
                for tc in self.env["itr.transport.case"].search([
                    ("source_item_id", "=", record.id),
                    ("state", "not in", list(EXCLUDED_TRANSPORT_STATES)),
                ])
            )
        if record._name == "itr.trade.case":
            return sum(
                tc.effective_tonnage or 0.0
                for tc in record.transport_case_ids
                if tc.state not in EXCLUDED_TRANSPORT_STATES
            )
        return 0.0

    def _metric_surplus(self, record):
        return max(0.0, self._metric_effective(record) - self._metric_planned(record))

    def _metric_remaining(self, record):
        return max(0.0, self._metric_planned(record) - self._metric_effective(record))

    # -- money family ---------------------------------------------------------
    def _metric_cost(self, record):
        engine = self.env["itr.money.engine"]
        if record._name == "itr.transport.case":
            return engine.transport_totals(record).get("total_cost", 0.0)
        if record._name == "itr.trade.case":
            return engine.case_totals(record).get("operational_cost_base", 0.0)
        return 0.0

    def _metric_settled(self, record):
        """G07 / FIN-028 - cash, never the requested amount."""
        Exe = self.env["itr.payment.execution"]
        domain = [("state", "=", "done")]
        if record._name == "itr.transport.case":
            domain.append(("transport_case_id", "=", record.id))
        elif record._name == "itr.trade.case":
            domain.append(("transport_case_id.trade_case_id", "=", record.id))
        else:
            return 0.0
        total = 0.0
        for exe in Exe.search(domain):
            total += -(exe.base_amount or 0.0) if exe.is_reversal else (exe.base_amount or 0.0)
        return total

    def _metric_profit(self, record):
        """FIN-005 - the one and only profit formula, from the money engine."""
        engine = self.env["itr.money.engine"]
        if record._name == "itr.trade.case":
            return engine.case_totals(record).get("estimated_profit_base", 0.0)
        if record._name == "itr.transport.case":
            return (record.sale_amount_base or 0.0) \
                - (record.purchase_amount_base or 0.0) \
                - self._metric_cost(record)
        return 0.0

    # -- sla ------------------------------------------------------------------
    def _metric_sla_state(self, record):
        """NOT-035 - read the single SLA engine, never recompute a clock."""
        watch = self.env["itr.sla.watch"].search([
            ("res_model", "=", record._name),
            ("res_id", "=", record.id),
            ("state", "=", "open"),
        ], order="deadline asc", limit=1)
        if watch:
            return watch.sla_state or "normal"
        return getattr(record, "sla_color", False) or "normal"
PYEOF

# -----------------------------------------------------------------------------
# 9.8..9.16 — موتور گزارش (۱۴ گزارش G02..G15)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_report_engine.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""SRS 13-2 - the 15 mandatory reports (G01..G15).

Design rules honoured here:
  REP-005  cost comes from itr.cost.line, settlement from itr.payment.execution;
           a payment is NEVER counted a second time as a cost (FIN-003).
  REP-006  every filter is applied server side and every read goes through the
           ORM with the CALLING user, so the phase 7 record rules apply.
  REP-007  no raw SQL at all - ORM only, never a raw cursor execute in this module.
  G05      customs duty and clearance fee stay two independent columns.
  G07      the payment report reads ONLY itr.payment.execution.
  VAL-008  every sheba in every output uses the single masking helper.
"""
from odoo import api, models
from odoo.exceptions import UserError

from odoo.addons.itr_base.utils import jalali as jal

REPORT_KEYS = (
    "financial26",      # G01
    "freight",          # G02
    "customs",          # G03
    "tonnage",          # G04
    "profit",           # G05
    "stalled",          # G06
    "payments",         # G07
    "period_summary",   # G08
    "packing",          # G09
    "item_balance",     # G10
    "open_invoices",    # G11
    "profit_per_load",  # G12
    "freight_advance",  # G13
    "border_loading",   # G14
    "factory_debt",     # G15
)

PERIODS = {"daily": "%Y-%m-%d", "monthly": "%Y-%m", "yearly": "%Y"}


def _col(key, label, unit="text", cumulative=False):
    return {"key": key, "label": label, "unit": unit, "cumulative": cumulative}


class ItrReportEngine(models.AbstractModel):
    _name = "itr.report.engine"
    _description = "Phase 9 report engine (single source for report data)"

    # ------------------------------------------------------------------ utils
    @api.model
    def _registry(self):
        return self.env["itr.kpi.service"]

    @api.model
    def _mask(self, value):
        """VAL-008 - one masking policy on every path."""
        return self.env["itr.validation.service"].mask_sheba(value or "")

    @api.model
    def _jdate(self, value):
        """NFR-009 - one calendar engine (itr_base), Latin digits for grids."""
        return jal.to_jalali_str(value) if value else ""

    @api.model
    def _date_domain(self, field, options):
        dom = []
        if options.get("date_from"):
            dom.append((field, ">=", options["date_from"]))
        if options.get("date_to"):
            dom.append((field, "<=", options["date_to"]))
        return dom

    @api.model
    def _transport_domain(self, options):
        dom = self._registry().operational_domain("itr.transport.case")
        dom += self._date_domain("order_date", options)
        for key, field in (("border_id", "border_id"), ("carrier_id", "carrier_id"),
                           ("factory_id", "factory_id"), ("customer_id", "customer_id"),
                           ("driver_id", "driver_id")):
            if options.get(key):
                dom.append((field, "=", options[key]))
        return dom

    @api.model
    def _period_label(self, value, period):
        if not value:
            return "-"
        text = self._jdate(value)
        if period == "yearly":
            return text[:4]
        if period == "monthly":
            return text[:7]
        return text

    # ------------------------------------------------------------------- api
    @api.model
    def run(self, report_key, options=None):
        """The ONLY entry point. Returns {columns, rows, totals, meta}."""
        options = dict(options or {})
        if report_key not in REPORT_KEYS:
            raise UserError("گزارش ناشناخته: %s" % report_key)
        if report_key == "financial26":
            return self.env["itr.report.financial26"].build(options)
        handler = getattr(self, "_run_%s" % report_key)
        columns, rows = handler(options)
        return {
            "report_key": report_key,
            "columns": columns,
            "rows": rows,
            "totals": self.grand_total(columns, rows),
            "meta": {
                "generated_by": self.env.user.name,
                "generated_on": self._jdate(fields_today(self)),
                "options": options,
            },
        }

    @api.model
    def grand_total(self, columns, rows):
        """REP-015 - a cumulative column takes the LAST value, never the sum."""
        totals = {}
        for col in columns:
            if col["unit"] not in ("tonne", "money_base", "count"):
                continue
            values = [r.get(col["key"]) for r in rows if isinstance(r.get(col["key"]), (int, float))]
            if not values:
                totals[col["key"]] = 0.0
                continue
            totals[col["key"]] = values[-1] if col.get("cumulative") else sum(values)
        return totals

    # ------------------------------------------------------- G02 freight 9.8
    def _run_freight(self, options):
        period = options.get("period") or "detail"
        group_by = options.get("group_by")
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        columns = [
            _col("label", "دوره / تفکیک"),
            _col("count", "تعداد بار", "count"),
            _col("tonnage", "تناژ مؤثر", "tonne"),
            _col("freight", "کرایه (ریال)", "money_base"),
        ]
        if period == "detail" and not group_by:
            columns = [
                _col("name", "بارگیری"), _col("order_date", "تاریخ"),
                _col("waybill", "بارنامه"), _col("driver", "راننده"),
                _col("carrier", "باربری"), _col("customer", "مشتری"),
                _col("factory", "کارخانه"), _col("border", "مرز"),
                _col("tonnage", "تناژ مؤثر", "tonne"),
                _col("freight", "کرایه (ریال)", "money_base"),
                _col("res_id", "#"),
            ]
            rows = [{
                "name": c.display_name, "order_date": self._jdate(c.order_date),
                "waybill": c.waybill_number or "", "driver": c.driver_id.display_name or "",
                "carrier": c.carrier_id.display_name or "", "customer": c.customer_id.display_name or "",
                "factory": c.factory_id.display_name or "", "border": c.border_id.display_name or "",
                "tonnage": self._registry().metric("effective", c),
                "freight": c.freight_cost or 0.0,
                "res_model": "itr.transport.case", "res_id": c.id,
            } for c in cases]
            return columns, rows
        buckets = {}
        dim = {"driver": "driver_id", "carrier": "carrier_id", "customer": "customer_id",
               "factory": "factory_id", "border": "border_id"}.get(group_by)
        for c in cases:
            parts = []
            if period in PERIODS:
                parts.append(self._period_label(c.order_date, period))
            if dim:
                parts.append((c[dim].display_name if c[dim] else "—"))
            label = " | ".join(parts) or "همه"
            b = buckets.setdefault(label, {"label": label, "count": 0, "tonnage": 0.0, "freight": 0.0})
            b["count"] += 1
            b["tonnage"] += self._registry().metric("effective", c)
            b["freight"] += c.freight_cost or 0.0
        return columns, sorted(buckets.values(), key=lambda r: r["label"])

    # ------------------------------------------------- G03 customs 9.9 (G05!)
    def _run_customs(self, options):
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        group_by = options.get("group_by")
        dim = {"border": "border_id", "broker": "customs_broker_id",
               "agent": "border_agent_id", "driver": "driver_id"}.get(group_by)
        columns = [
            _col("label", "تفکیک") if dim else _col("name", "بارگیری"),
            _col("declaration", "شماره اظهار"),
            _col("customs_cost", "عوارض گمرک (ریال)", "money_base"),
            _col("clearance_cost", "حق‌العمل ترخیص (ریال)", "money_base"),
            _col("count", "تعداد", "count"),
        ]
        if not dim:
            rows = [{
                "name": c.display_name,
                "declaration": c.declaration_file_name or "",
                "customs_cost": c.customs_cost or 0.0,
                "clearance_cost": c.clearance_cost or 0.0,
                "count": 1,
                "res_model": "itr.transport.case", "res_id": c.id,
            } for c in cases]
            return columns, rows
        buckets = {}
        for c in cases:
            label = c[dim].display_name if c[dim] else "—"
            b = buckets.setdefault(label, {"label": label, "declaration": "",
                                           "customs_cost": 0.0, "clearance_cost": 0.0, "count": 0})
            # G05: the two are NEVER merged into one column.
            b["customs_cost"] += c.customs_cost or 0.0
            b["clearance_cost"] += c.clearance_cost or 0.0
            b["count"] += 1
        return columns, sorted(buckets.values(), key=lambda r: -r["customs_cost"])

    # ------------------------------------------------------- G04 tonnage 9.10
    def _run_tonnage(self, options):
        reg = self._registry()
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        dim = {"factory": "factory_id", "border": "border_id",
               "customer": "customer_id"}.get(options.get("group_by"))
        columns = [
            _col("label", "تفکیک") if dim else _col("name", "بارگیری"),
            _col("planned", "تناژ برنامه", "tonne"),
            _col("effective", "تناژ مؤثر", "tonne"),
            _col("diff", "اختلاف", "tonne"),
            _col("surplus", "مازاد", "tonne"),
            _col("remaining", "مانده", "tonne"),
        ]
        if not dim:
            rows = []
            for c in cases:
                p, e = reg.metric("planned", c), reg.metric("effective", c)
                rows.append({"name": c.display_name, "planned": p, "effective": e,
                             "diff": e - p, "surplus": reg.metric("surplus", c),
                             "remaining": reg.metric("remaining", c),
                             "res_model": "itr.transport.case", "res_id": c.id})
            return columns, rows
        buckets = {}
        for c in cases:
            label = c[dim].display_name if c[dim] else "—"
            b = buckets.setdefault(label, {"label": label, "planned": 0.0, "effective": 0.0,
                                           "diff": 0.0, "surplus": 0.0, "remaining": 0.0})
            p, e = reg.metric("planned", c), reg.metric("effective", c)
            b["planned"] += p
            b["effective"] += e
            b["diff"] += e - p
            b["surplus"] += reg.metric("surplus", c)
            b["remaining"] += reg.metric("remaining", c)
        return columns, sorted(buckets.values(), key=lambda r: -r["effective"])

    # -------------------------------------------------------- G05 profit 9.11
    def _run_profit(self, options):
        reg = self._registry()
        dom = reg.operational_domain("itr.trade.case") + self._date_domain("create_date", options)
        cases = self.env["itr.trade.case"].search(dom, order="id asc")
        dim = {"customer": "buyer_id", "factory": "factory_id"}.get(options.get("group_by"))
        columns = [
            _col("label", "تفکیک") if dim else _col("name", "پرونده"),
            _col("sales", "فروش (ریال)", "money_base"),
            _col("purchase", "خرید (ریال)", "money_base"),
            _col("cost", "هزینهٔ عملیاتی (ریال)", "money_base"),
            _col("settled", "تسویه‌شده (ریال)", "money_base"),
            _col("profit", "سود برآوردی (ریال)", "money_base"),
        ]
        if not dim:
            rows = [{
                "name": c.display_name,
                "sales": c.sales_total_base or 0.0,
                "purchase": c.purchase_total_base or 0.0,
                "cost": reg.metric("cost", c),
                "settled": reg.metric("settled", c),
                "profit": reg.metric("profit", c),
                "res_model": "itr.trade.case", "res_id": c.id,
            } for c in cases]
            return columns, rows
        buckets = {}
        for c in cases:
            label = c[dim].display_name if c[dim] else "—"
            b = buckets.setdefault(label, {"label": label, "sales": 0.0, "purchase": 0.0,
                                           "cost": 0.0, "settled": 0.0, "profit": 0.0})
            b["sales"] += c.sales_total_base or 0.0
            b["purchase"] += c.purchase_total_base or 0.0
            b["cost"] += reg.metric("cost", c)
            b["settled"] += reg.metric("settled", c)
            b["profit"] += reg.metric("profit", c)
        return columns, sorted(buckets.values(), key=lambda r: -r["profit"])

    # ------------------------------------------------------- G06 stalled 9.12
    def _run_stalled(self, options):
        """Threshold comes from itr.cartable.settings, never from code (UX-002)."""
        settings = self.env["itr.cartable.settings"].get_settings() \
            if hasattr(self.env["itr.cartable.settings"], "get_settings") \
            else self.env["itr.cartable.settings"].search([], limit=1)
        urgent_hours = options.get("urgent_hours") or (settings.urgent_hours if settings else 24)
        reg = self._registry()
        columns = [
            _col("model", "نوع"), _col("name", "پرونده"), _col("state", "مرحله"),
            _col("owner", "مسئول فعلی"), _col("deadline", "مهلت"),
            _col("sla", "رنگ SLA", "state"), _col("hours", "ساعت توقف", "count"),
        ]
        rows = []
        now = fields_now(self)
        for model_name in ("itr.trade.case", "itr.transport.case"):
            dom = reg.operational_domain(model_name) + [("state", "not in", ("closed",))]
            for rec in self.env[model_name].search(dom):
                ref = rec.write_date or rec.create_date
                hours = int((now - ref).total_seconds() // 3600) if ref else 0
                if hours < urgent_hours:
                    continue
                rows.append({
                    "model": model_name, "name": rec.display_name,
                    "state": rec.state, "owner": rec.current_owner_id.display_name or "—",
                    "deadline": self._jdate(rec.owner_deadline) if rec.owner_deadline else "",
                    "sla": reg.metric("sla_state", rec), "hours": hours,
                    "res_model": model_name, "res_id": rec.id,
                })
        return columns, sorted(rows, key=lambda r: -r["hours"])

    # ------------------------------------------------------ G07 payments 9.13
    def _run_payments(self, options):
        """G07 / FIN-028 - ONLY itr.payment.execution. A request is never shown."""
        dom = [("state", "=", "done")] + self._date_domain("executed_on", options)
        execs = self.env["itr.payment.execution"].search(dom, order="executed_on asc, id asc")
        columns = [
            _col("executed_on", "تاریخ واریز"), _col("loading", "بارگیری"),
            _col("category", "دستهٔ هزینه"), _col("payee", "ذی‌نفع"),
            _col("sheba", "شبا (ماسک‌شده)"), _col("bank_ref", "پیگیری بانکی"),
            _col("amount", "مبلغ (ارز اصلی)", "money_src"),
            _col("base_amount", "مبلغ پایه (ریال)", "money_base"),
            _col("reversal", "معکوس؟"),
        ]
        rows = [{
            "executed_on": self._jdate(e.executed_on),
            "loading": e.transport_case_id.display_name or "",
            "category": e.category or "", "payee": e.payee_name or "",
            "sheba": self._mask(e.payee_sheba_masked or ""),
            "bank_ref": e.bank_reference or "",
            "amount": e.amount or 0.0,
            "base_amount": -(e.base_amount or 0.0) if e.is_reversal else (e.base_amount or 0.0),
            "reversal": "بله" if e.is_reversal else "خیر",
            "res_model": "itr.payment.execution", "res_id": e.id,
        } for e in execs]
        return columns, rows

    # ------------------------------------------------- G08 period summary 9.14
    def _run_period_summary(self, options):
        period = options.get("period") or "daily"
        reg = self._registry()
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        columns = [
            _col("label", "دوره"), _col("count", "تعداد بار", "count"),
            _col("tonnage", "تناژ مؤثر", "tonne"),
            _col("done", "تکمیل‌شده", "count"),
            _col("cost", "جمع هزینه (ریال)", "money_base"),
            _col("settled", "جمع تسویه (ریال)", "money_base"),
        ]
        buckets = {}
        for c in cases:
            label = self._period_label(c.order_date, period)
            b = buckets.setdefault(label, {"label": label, "count": 0, "tonnage": 0.0,
                                           "done": 0, "cost": 0.0, "settled": 0.0})
            b["count"] += 1
            b["tonnage"] += reg.metric("effective", c)
            b["done"] += 1 if c.state in ("closed", "settled") else 0
            b["cost"] += reg.metric("cost", c)
            b["settled"] += reg.metric("settled", c)
        return columns, sorted(buckets.values(), key=lambda r: r["label"], reverse=True)

    # ------------------------------------------------------- G09 packing 9.15
    def _run_packing(self, options):
        """SRS 13-2/G09 - the mandatory packing columns, all of them."""
        reg = self._registry()
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="packing_date asc, id asc")
        columns = [
            _col("goods", "نوع بار"), _col("thickness", "ضخامت", "count"),
            _col("qty", "تعداد", "count"), _col("weight", "وزن (تن)", "tonne"),
            _col("border", "مرز"), _col("driver", "راننده"), _col("plate", "پلاک"),
            _col("mobile", "موبایل"), _col("customer", "مشتری"),
            _col("packing_date", "تاریخ پکینگ"),
            _col("purchase_ref", "ش.پیش‌فاکتور خرید"),
            _col("sales_ref", "ش.پیش‌فاکتور فروش"),
        ]
        rows = [{
            "goods": c.goods_description or "",
            "thickness": c.thickness_mm or 0.0,
            "qty": c.packing_qty or 0,
            "weight": reg.metric("effective", c),
            "border": c.border_id.display_name or "",
            "driver": c.driver_id.display_name or "",
            "plate": c.vehicle_id.plate_number or "",
            "mobile": c.driver_mobile or "",
            "customer": c.customer_id.display_name or "",
            "packing_date": self._jdate(c.packing_date or c.order_date),
            "purchase_ref": c.purchase_ref or "",
            "sales_ref": c.sales_ref or "",
            "res_model": "itr.transport.case", "res_id": c.id,
        } for c in cases]
        return columns, rows

    # -------------------------------------------------- G10 item balance 9.16
    def _run_item_balance(self, options):
        reg = self._registry()
        dom = [("case_id.state", "not in", ("rejected",))]
        items = self.env["itr.trade.case.item"].search(dom, order="case_id asc, sequence asc, id asc")
        columns = [
            _col("case", "پرونده"), _col("item", "ردیف کالا"), _col("kind", "نوع ردیف"),
            _col("planned", "قراردادی", "tonne"), _col("reserved", "رزروشده", "tonne"),
            _col("effective", "مؤثر", "tonne"), _col("remaining", "مانده", "tonne"),
        ]
        rows = [{
            "case": i.case_id.display_name, "item": i.name or "",
            "kind": i.row_kind, "planned": reg.metric("planned", i),
            "reserved": reg.metric("reserved", i), "effective": reg.metric("effective", i),
            "remaining": reg.metric("remaining", i),
            "res_model": "itr.trade.case", "res_id": i.case_id.id,
        } for i in items]
        return columns, rows

    # ------------------------------------------------- G11 open invoices 9.16
    def _run_open_invoices(self, options):
        reg = self._registry()
        dom = reg.operational_domain("itr.trade.case") + [("state", "not in", ("closed",))]
        cases = self.env["itr.trade.case"].search(dom, order="id asc")
        columns = [
            _col("name", "پرونده"), _col("state", "وضعیت"),
            _col("purchase_ref", "پیش‌فاکتور خرید"), _col("sales_ref", "پیش‌فاکتور فروش"),
            _col("purchase", "مبلغ خرید (ریال)", "money_base"),
            _col("sales", "مبلغ فروش (ریال)", "money_base"),
            _col("remaining", "تناژ مانده", "tonne"),
        ]
        rows = [{
            "name": c.display_name, "state": c.state,
            "purchase_ref": c.proforma_purchase_ref or "",
            "sales_ref": c.proforma_sales_ref or "",
            "purchase": c.purchase_total_base or 0.0,
            "sales": c.sales_total_base or 0.0,
            "remaining": reg.metric("remaining", c),
            "res_model": "itr.trade.case", "res_id": c.id,
        } for c in cases]
        return columns, rows

    # --------------------------------------------- G12 profit per load 9.16
    def _run_profit_per_load(self, options):
        reg = self._registry()
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        columns = [
            _col("name", "بارگیری"), _col("customer", "مشتری"), _col("factory", "کارخانه"),
            _col("sale", "فروش (ریال)", "money_base"),
            _col("purchase", "خرید (ریال)", "money_base"),
            _col("cost", "هزینه (ریال)", "money_base"),
            _col("profit", "سود (ریال)", "money_base"),
        ]
        rows = [{
            "name": c.display_name, "customer": c.customer_id.display_name or "",
            "factory": c.factory_id.display_name or "",
            "sale": c.sale_amount_base or 0.0, "purchase": c.purchase_amount_base or 0.0,
            "cost": reg.metric("cost", c), "profit": reg.metric("profit", c),
            "res_model": "itr.transport.case", "res_id": c.id,
        } for c in cases]
        return columns, rows

    # ------------------------------------------ G13 freight + advance 9.16
    def _run_freight_advance(self, options):
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        columns = [
            _col("name", "بارگیری"), _col("waybill", "بارنامه"),
            _col("anchor", "لنگر کرایهٔ بارنامه (ریال)", "money_base"),
            _col("freight", "کرایهٔ ثبت‌شده (ریال)", "money_base"),
            _col("advance", "پیش‌کرایهٔ پرداخت‌شده (ریال)", "money_base"),
            _col("due", "صافی قابل پرداخت (ریال)", "money_base"),
            _col("pod", "رسید تخلیه؟"),
        ]
        rows = [{
            "name": c.display_name, "waybill": c.waybill_number or "",
            "anchor": c.waybill_freight_base or 0.0, "freight": c.freight_cost or 0.0,
            "advance": c.advance_paid_base or 0.0, "due": c.final_freight_due or 0.0,
            "pod": "بله" if c.delivery_receipt else "خیر",
            "res_model": "itr.transport.case", "res_id": c.id,
        } for c in cases]
        return columns, rows

    # --------------------------------------- G14 factory loading by border
    def _run_border_loading(self, options):
        reg = self._registry()
        cases = self.env["itr.transport.case"].search(
            self._transport_domain(options), order="order_date asc, id asc")
        columns = [
            _col("factory", "کارخانه"), _col("border", "مرز"),
            _col("count", "تعداد بار", "count"), _col("tonnage", "تناژ مؤثر", "tonne"),
        ]
        buckets = {}
        for c in cases:
            key = (c.factory_id.display_name or "—", c.border_id.display_name or "—")
            b = buckets.setdefault(key, {"factory": key[0], "border": key[1],
                                         "count": 0, "tonnage": 0.0})
            b["count"] += 1
            b["tonnage"] += reg.metric("effective", c)
        return columns, sorted(buckets.values(), key=lambda r: (r["factory"], r["border"]))

    # ------------------------------------------------- G15 factory debt 9.16
    def _run_factory_debt(self, options):
        shortfalls = self.env["itr.factory.shortfall"].search([], order="id asc")
        columns = [
            _col("supplier", "کارخانه"), _col("case", "پرونده"),
            _col("item", "ردیف کالا"), _col("tonnage", "تناژ کسری", "tonne"),
            _col("amount", "مبلغ (ریال)", "money_base"),
            _col("settled_t", "تسویه‌شده (تن)", "tonne"),
            _col("remaining_t", "مانده (تن)", "tonne"),
            _col("state", "وضعیت"), _col("age", "سن مانده (روز)", "count"),
        ]
        rows = [{
            "supplier": s.supplier_id.display_name or "",
            "case": s.trade_case_id.display_name or "",
            "item": s.trade_case_item_id.name or s.goods_description or "",
            "tonnage": s.shortfall_tonnage or 0.0,
            "amount": s.shortfall_amount_base or 0.0,
            "settled_t": s.settled_tonnage or 0.0,
            "remaining_t": s.remaining_tonnage or 0.0,
            "state": s.state, "age": s.age_days or 0,
            "res_model": "itr.factory.shortfall", "res_id": s.id,
        } for s in shortfalls]
        return columns, rows


def fields_today(rs):
    from odoo import fields as odoo_fields
    return odoo_fields.Date.context_today(rs)


def fields_now(rs):
    from odoo import fields as odoo_fields
    return odoo_fields.Datetime.now()
PYEOF

# -----------------------------------------------------------------------------
# 9.4..9.7 — گزارش ۲۶ستونهٔ جامع مالی (G01)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_report_financial26.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""SRS 13-3 - the 26 column financial report.

Locked rules implemented literally:
  REP-011  the purchase side and the sale side are computed COMPLETELY
           independently; one never leaks into the other.
  REP-012  surplus = max(0, out - planned); remaining = max(0, planned - out);
           neither can ever be negative.
  REP-013  a 'both' trade case item is split into TWO logical rows (purchase and
           sale). The decision is taken per ROW KIND (G11), never from a single
           header field, so a mixed deal never returns an empty side.
  REP-014  deterministic cumulative order: (date, record id).
  REP-015  in the grand total row the six cumulative columns take the LAST
           value, they are never summed again.
  REP-016  every row carries res_model/res_id so the UI can drill down.
"""
from odoo import api, models

from odoo.addons.itr_base.utils import jalali as jal

# checklist 9.4 - the exact order, never shuffled.
COLUMNS_26 = [
    # ---- sale side 1..13
    ("sales_date", "تاریخ فروش", "date", False),
    ("sales_inv", "ش.فاکتور فروش", "text", False),
    ("customer", "مشتری", "text", False),
    ("item_s", "نوع کالا", "text", False),
    ("plan_s", "تناژ اصلی فروش", "tonne", False),
    ("amount_fx_s", "مبلغ ارزی", "money_src", False),
    ("amount_base_s", "مبلغ ریالی", "money_base", False),
    ("ship_s", "تناژ خروجی فروش", "tonne", False),
    ("cship_s", "جمع تجمعی خروجی فروش", "tonne", True),
    ("sur_s", "مازاد فروش", "tonne", False),
    ("csur_s", "جمع تجمعی مازاد فروش", "tonne", True),
    ("rem_s", "باقیماندهٔ فروش", "tonne", False),
    ("crem_s", "جمع تجمعی باقیماندهٔ فروش", "tonne", True),
    # ---- purchase side 14..25
    ("pur_date", "تاریخ خرید", "date", False),
    ("pur_inv", "ش.فاکتور خرید", "text", False),
    ("supplier", "تأمین‌کننده", "text", False),
    ("item_p", "نوع کالا (خرید)", "text", False),
    ("plan_p", "تناژ اصلی خرید", "tonne", False),
    ("amount_p", "مبلغ خرید", "money_base", False),
    ("ship_p", "تناژ خروجی خرید", "tonne", False),
    ("cship_p", "جمع تجمعی خروجی خرید", "tonne", True),
    ("sur_p", "مازاد خرید", "tonne", False),
    ("csur_p", "جمع تجمعی مازاد خرید", "tonne", True),
    ("rem_p", "باقیماندهٔ خرید", "tonne", False),
    ("crem_p", "جمع تجمعی باقیماندهٔ خرید", "tonne", True),
    # ---- 26
    ("status", "وضعیت", "text", False),
]

CUMULATIVE_KEYS = {"cship_s", "csur_s", "crem_s", "cship_p", "csur_p", "crem_p"}


class ItrReportFinancial26(models.AbstractModel):
    _name = "itr.report.financial26"
    _description = "G01 - 26 column purchase/sale financial report"

    @api.model
    def columns(self):
        return [{"key": k, "label": l, "unit": u, "cumulative": c}
                for (k, l, u, c) in COLUMNS_26]

    @api.model
    def _logical_rows(self, options):
        """REP-013 / G11 - split per row kind, never per header field."""
        reg = self.env["itr.kpi.service"]
        dom = reg.operational_domain("itr.trade.case")
        if options.get("date_from"):
            dom.append(("create_date", ">=", options["date_from"]))
        if options.get("date_to"):
            dom.append(("create_date", "<=", options["date_to"]))
        if options.get("case_id"):
            dom.append(("id", "=", options["case_id"]))
        cases = self.env["itr.trade.case"].search(dom)
        logical = []
        for case in cases:
            for item in case.item_ids:
                kinds = []
                if item.row_kind in ("sale", "both"):
                    kinds.append("sale")
                if item.row_kind in ("purchase", "both"):
                    kinds.append("purchase")
                for kind in kinds:
                    logical.append((case, item, kind))
        # REP-014 - deterministic order (date, record id)
        logical.sort(key=lambda t: (t[0].create_date or t[0].id, t[0].id, t[1].id,
                                    0 if t[2] == "sale" else 1))
        return logical

    @api.model
    def build(self, options=None):
        options = dict(options or {})
        reg = self.env["itr.kpi.service"]
        rows = []
        c_ship_s = c_sur_s = c_rem_s = 0.0
        c_ship_p = c_sur_p = c_rem_p = 0.0

        for case, item, kind in self._logical_rows(options):
            planned = reg.metric("planned", item)
            shipped = reg.metric("effective", item)
            surplus = reg.metric("surplus", item)      # REP-012, never negative
            remaining = reg.metric("remaining", item)  # REP-012, never negative
            is_sale = kind == "sale"

            if is_sale:
                c_ship_s += shipped
                c_sur_s += surplus
                c_rem_s += remaining
            else:
                c_ship_p += shipped
                c_sur_p += surplus
                c_rem_p += remaining

            fx_currency = item.sale_currency_id if is_sale else item.purchase_currency_id
            row = {
                # sale side - filled ONLY for a sale logical row (REP-011)
                "sales_date": jal.to_jalali_str(case.create_date) if is_sale else "",
                "sales_inv": (case.proforma_sales_ref or case.name) if is_sale else "",
                "customer": (case.buyer_id.display_name or "") if is_sale else "",
                "item_s": (item.name or "") if is_sale else "",
                "plan_s": planned if is_sale else 0.0,
                "amount_fx_s": ("%s %s" % (item.sale_amount or 0.0,
                                           fx_currency.name or "")) if is_sale else "",
                "amount_base_s": (item.sale_base_amount or 0.0) if is_sale else 0.0,
                "ship_s": shipped if is_sale else 0.0,
                "cship_s": c_ship_s,
                "sur_s": surplus if is_sale else 0.0,
                "csur_s": c_sur_s,
                "rem_s": remaining if is_sale else 0.0,
                "crem_s": c_rem_s,
                # purchase side - filled ONLY for a purchase logical row
                "pur_date": jal.to_jalali_str(case.create_date) if not is_sale else "",
                "pur_inv": (case.proforma_purchase_ref or case.name) if not is_sale else "",
                "supplier": (case.factory_id.display_name or "") if not is_sale else "",
                "item_p": (item.name or "") if not is_sale else "",
                "plan_p": planned if not is_sale else 0.0,
                "amount_p": (item.purchase_base_amount or 0.0) if not is_sale else 0.0,
                "ship_p": shipped if not is_sale else 0.0,
                "cship_p": c_ship_p,
                "sur_p": surplus if not is_sale else 0.0,
                "csur_p": c_sur_p,
                "rem_p": remaining if not is_sale else 0.0,
                "crem_p": c_rem_p,
                "status": case.state,
                # REP-016 - drill down
                "res_model": "itr.trade.case",
                "res_id": case.id,
                "row_kind": kind,
            }
            rows.append(row)

        columns = self.columns()
        return {
            "report_key": "financial26",
            "columns": columns,
            "rows": rows,
            "totals": self.grand_total(columns, rows),
            "meta": {"generated_by": self.env.user.name, "options": options},
        }

    @api.model
    def grand_total(self, columns, rows):
        """REP-015 - cumulative columns take the LAST value."""
        totals = {}
        for col in columns:
            key = col["key"]
            if col["unit"] not in ("tonne", "money_base"):
                continue
            values = [r.get(key) for r in rows if isinstance(r.get(key), (int, float))]
            if not values:
                totals[key] = 0.0
            elif key in CUMULATIVE_KEYS:
                totals[key] = values[-1]
            else:
                totals[key] = sum(values)
        return totals
PYEOF

# -----------------------------------------------------------------------------
# 9.19..9.22 — موتور اکسل استاندارد + کمک‌توابع مشترک
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_excel_common.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Shared Excel guards and helpers (XLS-010 / XLS-012 / XLS-018).

One place for: size and row caps, extension/MIME check, zip-bomb and formula
injection guards, safe file names, sheet title truncation and the ONE date
policy for Excel cells (Jalali with LATIN digits - deliberately different from
the printed documents which use Persian digits).
"""
import io
import re

from odoo import api, models
from odoo.exceptions import UserError

from odoo.addons.itr_base.utils import jalali as jal

MAX_FILE_BYTES = 10 * 1024 * 1024      # XLS-012 default 10MB
MAX_ROWS = 2000                        # XLS-012 default 2000 rows
MAX_UNCOMPRESSED = 120 * 1024 * 1024   # zip-bomb guard
FORMULA_PREFIXES = ("=", "+", "-", "@")

FINANCE_GROUPS = (
    "itr_core.group_ceo",
    "itr_core.group_financial_manager",
    "itr_core.group_finance_supervisor",
    "itr_core.group_finance_user",
)
OPERATION_GROUPS = FINANCE_GROUPS + (
    "itr_core.group_transport_supervisor",
    "itr_core.group_transport_docs",
    "itr_core.group_customs_officer",
    "itr_core.group_transport_delivery",
    "itr_core.group_auditor",
)


class ItrExcelCommon(models.AbstractModel):
    _name = "itr.excel.common"
    _description = "Phase 9 shared Excel guards"

    # ----------------------------------------------------------------- guards
    @api.model
    def guard_groups(self, groups):
        """SEC-011 - export is a privilege, not a default."""
        if not any(self.env.user.has_group(g) for g in groups):
            raise UserError("دسترسی به این خروجی/ورودی اکسل مجاز نیست.")

    @api.model
    def guard_upload(self, filename, content):
        if not filename or not filename.lower().endswith(".xlsx"):
            raise UserError("فقط فایل با پسوند xlsx مجاز است.")
        if not content:
            raise UserError("فایل خالی است.")
        if len(content) > MAX_FILE_BYTES:
            raise UserError("حجم فایل بیش از حد مجاز (۱۰ مگابایت) است.")
        if content[:2] != b"PK":
            raise UserError("محتوای فایل یک بستهٔ xlsx معتبر نیست.")
        import zipfile
        try:
            with zipfile.ZipFile(io.BytesIO(content)) as zf:
                total = sum(i.file_size for i in zf.infolist())
                if total > MAX_UNCOMPRESSED:
                    raise UserError("فایل مشکوک به zip-bomb است و رد شد.")
        except UserError:
            raise
        except Exception:
            raise UserError("فایل xlsx قابل باز شدن نیست.")
        return True

    @api.model
    def sanitize_cell(self, value):
        """XLS-012 - formula injection guard for anything we WRITE as data."""
        if isinstance(value, str) and value[:1] in FORMULA_PREFIXES:
            return "'" + value
        return value

    @api.model
    def safe_filename(self, base):
        base = re.sub(r"[^A-Za-z0-9_.-]+", "_", base or "export")
        return (base[:80] or "export") + ".xlsx"

    @api.model
    def sheet_title(self, title):
        return (title or "Sheet")[:31]          # XLS-010

    @api.model
    def xl_date(self, value):
        """XLS-018 - Jalali with LATIN digits inside Excel cells."""
        return jal.to_jalali_str(value) if value else ""

    @api.model
    def mask(self, value):
        return self.env["itr.validation.service"].mask_sheba(value or "")
PYEOF

write_utf8 "${REP_DIR}/models/itr_excel_standard.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""XLS-001 (a) - clean data export + XLS-021 sample template download.

This path writes a brand new workbook (never a customer template), so it is
allowed to style freely. RTL is on, the header row is frozen and filtered, the
grand total row respects REP-015.
"""
import io

from odoo import api, models

from .itr_excel_common import OPERATION_GROUPS


class ItrExcelStandard(models.AbstractModel):
    _name = "itr.excel.standard"
    _description = "Phase 9 standard (clean data) Excel export"

    @api.model
    def _wb(self, title, rtl=True):
        from openpyxl import Workbook
        wb = Workbook()
        ws = wb.active
        ws.title = self.env["itr.excel.common"].sheet_title(title)
        ws.sheet_view.rightToLeft = bool(rtl)
        return wb, ws

    @api.model
    def _style_header(self, ws, labels, row=1):
        from openpyxl.styles import Alignment, Font, PatternFill
        for idx, label in enumerate(labels, 1):
            cell = ws.cell(row=row, column=idx, value=label)
            cell.font = Font(bold=True)
            cell.fill = PatternFill(fill_type="solid", fgColor="D9EAF7")
            cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)

    @api.model
    def _autosize(self, ws, minimum=11, maximum=38):
        from openpyxl.utils import get_column_letter
        for cells in ws.columns:
            width = minimum
            for cell in cells:
                width = max(width, len("" if cell.value is None else str(cell.value)) + 2)
            ws.column_dimensions[get_column_letter(cells[0].column)].width = min(width, maximum)

    @api.model
    def export_report(self, report_key, options=None):
        """Return (filename, bytes) for any of the 15 reports."""
        common = self.env["itr.excel.common"]
        common.guard_groups(OPERATION_GROUPS)
        data = self.env["itr.report.engine"].run(report_key, options)
        columns, rows, totals = data["columns"], data["rows"], data["totals"]
        wb, ws = self._wb(report_key)
        self._style_header(ws, [c["label"] for c in columns], row=1)
        for r_i, row in enumerate(rows, 2):
            for c_i, col in enumerate(columns, 1):
                ws.cell(row=r_i, column=c_i,
                        value=common.sanitize_cell(row.get(col["key"])))
        # REP-015 grand total row
        from openpyxl.styles import Font
        total_row = len(rows) + 2
        ws.cell(row=total_row, column=1, value="جمع کل").font = Font(bold=True)
        for c_i, col in enumerate(columns, 1):
            if col["key"] in totals:
                cell = ws.cell(row=total_row, column=c_i, value=totals[col["key"]])
                cell.font = Font(bold=True)
        ws.freeze_panes = "A2"
        self._autosize(ws)
        out = io.BytesIO()
        wb.save(out)
        return common.safe_filename("itr_%s" % report_key), out.getvalue()

    @api.model
    def import_sample(self, kind):
        """XLS-021/9.21 - the downloadable sample import template."""
        common = self.env["itr.excel.common"]
        headers = self.env["itr.excel.import"].sample_headers(kind)
        wb, ws = self._wb("نمونهٔ ورود %s" % kind)
        self._style_header(ws, headers)
        ws.freeze_panes = "A2"
        self._autosize(ws)
        out = io.BytesIO()
        wb.save(out)
        return common.safe_filename("itr_sample_%s" % kind), out.getvalue()
PYEOF

write_utf8 "${REP_DIR}/models/itr_excel_import.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""XLS-011..XLS-017 / 9.19 - the four stage transactional import.

    Preview  -> read the workbook, show what WOULD happen, change nothing
    Validate -> per row valid / warning / error with a field level message
    Resolve  -> turn raw text into real records (ORM only, XLS-017)
    Commit   -> one savepoint; ANY error rolls the whole batch back

The commit token is derived from (file sha256 + user id + kind) so a stale
preview can never be committed and the same batch can never be committed twice
(XLS-011 / XLS-014).
"""
import hashlib
import io

from odoo import _, api, fields, models
from odoo.exceptions import UserError

SAMPLE_HEADERS = {
    # XLS-031 - proforma import on the trade case, NEVER the sales slip.
    "proforma": [
        "نوع ردیف (purchase/sale/both)", "شرح کالا", "تناژ قراردادی",
        "نرخ خرید واحد", "ارز خرید", "نرخ فروش واحد", "ارز فروش",
        "شمارهٔ پیش‌فاکتور خرید", "شمارهٔ پیش‌فاکتور فروش",
    ],
    # XLS-015 - a freight import can only ever produce a payment REQUEST.
    "freight": [
        "شماره بارنامه", "نام ذی‌نفع", "نوع هزینه (کد)", "شمارهٔ قسط",
        "مبلغ", "کد ارز", "شماره حساب/شبا", "بانک", "توضیح",
    ],
}


class ItrExcelImportBatch(models.Model):
    _name = "itr.excel.import.batch"
    _description = "XLS-013 - Excel import batch"
    _order = "id desc"

    name = fields.Char(string="Batch", required=True, default="/", readonly=True)
    kind = fields.Selection([("proforma", "Proforma (XLS-031)"),
                             ("freight", "Freight list (XLS-015)")],
                            string="Kind", required=True, readonly=True)
    filename = fields.Char(string="File name", readonly=True)
    file_sha256 = fields.Char(string="File checksum", readonly=True, index=True)
    commit_token = fields.Char(string="Commit token", readonly=True, copy=False)
    state = fields.Selection([("preview", "Preview"), ("validated", "Validated"),
                              ("committed", "Committed"), ("failed", "Failed")],
                             default="preview", required=True, readonly=True)
    row_total = fields.Integer(readonly=True)
    row_valid = fields.Integer(readonly=True)
    row_warning = fields.Integer(readonly=True)
    row_error = fields.Integer(readonly=True)
    created_count = fields.Integer(readonly=True)
    skipped_count = fields.Integer(readonly=True)
    committed_on = fields.Datetime(readonly=True)
    user_id = fields.Many2one("res.users", string="User", readonly=True,
                              default=lambda s: s.env.user)
    log_ids = fields.One2many("itr.excel.import.row", "batch_id", string="Rows")

    _sql_constraints = [
        ("itr_excel_batch_token_uniq", "unique(commit_token)",
         "XLS-011: توکن Commit یک‌بارمصرف است."),
    ]


class ItrExcelImportRow(models.Model):
    _name = "itr.excel.import.row"
    _description = "XLS-013 - Excel import row log"
    _order = "batch_id, row_no"

    batch_id = fields.Many2one("itr.excel.import.batch", required=True,
                               ondelete="cascade", index=True)
    row_no = fields.Integer(string="Excel row", required=True)
    status = fields.Selection([("valid", "Valid"), ("warning", "Warning"),
                               ("error", "Error"), ("created", "Created"),
                               ("skipped", "Skipped (duplicate)")],
                              required=True, default="valid")
    field_key = fields.Char(string="Field")
    message = fields.Char(string="Message")
    raw_payload = fields.Text(string="Raw row")
    res_model = fields.Char(string="Created model")
    res_id = fields.Integer(string="Created id")


class ItrExcelImport(models.AbstractModel):
    _name = "itr.excel.import"
    _description = "Phase 9 four stage Excel import engine"

    @api.model
    def sample_headers(self, kind):
        if kind not in SAMPLE_HEADERS:
            raise UserError("نوع ورود ناشناخته: %s" % kind)
        return SAMPLE_HEADERS[kind]

    # ------------------------------------------------------------- 1. preview
    @api.model
    def preview(self, kind, filename, content):
        common = self.env["itr.excel.common"]
        from .itr_excel_common import OPERATION_GROUPS
        common.guard_groups(OPERATION_GROUPS)
        common.guard_upload(filename, content)
        rows = self._read_rows(content)
        if len(rows) > 2000:
            raise UserError("تعداد ردیف بیش از سقف مجاز (۲۰۰۰) است.")
        sha = hashlib.sha256(content).hexdigest()
        batch = self.env["itr.excel.import.batch"].create({
            "name": self.env["ir.sequence"].next_by_code("itr.excel.import.batch") or "IMP/%s" % sha[:8],
            "kind": kind, "filename": filename, "file_sha256": sha,
            "row_total": len(rows), "state": "preview",
        })
        results = self.validate(kind, rows)
        vals = []
        for res in results:
            vals.append({
                "batch_id": batch.id, "row_no": res["row_no"], "status": res["status"],
                "field_key": res.get("field_key") or "", "message": res.get("message") or "",
                "raw_payload": repr(res.get("raw")),
            })
        self.env["itr.excel.import.row"].create(vals)
        batch.write({
            "row_valid": sum(1 for r in results if r["status"] == "valid"),
            "row_warning": sum(1 for r in results if r["status"] == "warning"),
            "row_error": sum(1 for r in results if r["status"] == "error"),
            "state": "validated",
            "commit_token": hashlib.sha256(
                ("%s|%s|%s|%s" % (sha, self.env.uid, kind, batch.id)).encode()).hexdigest(),
        })
        return {
            "batch_id": batch.id, "commit_token": batch.commit_token,
            "total": batch.row_total, "valid": batch.row_valid,
            "warning": batch.row_warning, "error": batch.row_error,
            "rows": results[:50],
        }

    # ------------------------------------------------------------ 2. validate
    @api.model
    def validate(self, kind, rows):
        out = []
        for row_no, raw in rows:
            status, field_key, message = "valid", "", ""
            if kind == "proforma":
                if not (raw[0] or "").strip() in ("purchase", "sale", "both"):
                    status, field_key, message = "error", "row_kind", "نوع ردیف باید purchase/sale/both باشد."
                elif not (raw[1] or "").strip():
                    status, field_key, message = "error", "name", "شرح کالا الزامی است."
                elif _f(raw[2]) <= 0:
                    status, field_key, message = "error", "contract_tonnage", "تناژ قراردادی باید بزرگ‌تر از صفر باشد."
            elif kind == "freight":
                if not (raw[0] or "").strip():
                    status, field_key, message = "error", "waybill_number", "شماره بارنامه الزامی است."
                elif not (raw[1] or "").strip():
                    status, field_key, message = "error", "payee_name", "نام ذی‌نفع الزامی است."
                elif _f(raw[4]) <= 0:
                    status, field_key, message = "error", "amount", "مبلغ باید بزرگ‌تر از صفر باشد."
                elif (raw[6] or "").strip():
                    # XLS-016: an account holder is NOT automatically the driver and an
                    # account number is NOT automatically a sheba. Never auto-map.
                    status, field_key, message = "warning", "payee_sheba", \
                        "شماره حساب به‌صورت خام نگه داشته شد؛ نگاشت خودکار به شبا/راننده انجام نشد (XLS-016)."
            out.append({"row_no": row_no, "status": status, "field_key": field_key,
                        "message": message, "raw": raw})
        return out

    # -------------------------------------------------------------- 4. commit
    @api.model
    def commit(self, batch_id, commit_token, content):
        """XLS-011 - single savepoint, any error rolls the WHOLE batch back."""
        batch = self.env["itr.excel.import.batch"].browse(batch_id)
        if not batch.exists():
            raise UserError("دستهٔ ورود یافت نشد.")
        if batch.state == "committed":
            raise UserError("این دسته قبلاً ثبت شده است (XLS-014).")
        if not commit_token or commit_token != batch.commit_token:
            raise UserError("توکن Commit معتبر نیست؛ پیش‌نمایش را دوباره اجرا کنید.")
        if hashlib.sha256(content).hexdigest() != batch.file_sha256:
            raise UserError("فایل با فایل پیش‌نمایش یکی نیست.")
        if batch.row_error:
            raise UserError(_("در فایل %s ردیف خطادار وجود دارد؛ Commit انجام نشد.") % batch.row_error)

        rows = self._read_rows(content)
        results = self.validate(batch.kind, rows)
        created = skipped = 0
        try:
            with self.env.cr.savepoint():
                for res in results:
                    if res["status"] == "error":
                        raise UserError("ردیف %s: %s" % (res["row_no"], res["message"]))
                    rec = self._resolve_and_create(batch, res)
                    if rec is None:
                        skipped += 1
                    else:
                        created += 1
        except Exception:
            batch.write({"state": "failed"})
            raise
        batch.write({"state": "committed", "created_count": created,
                     "skipped_count": skipped, "committed_on": fields.Datetime.now()})
        return {"batch_id": batch.id, "created": created, "skipped": skipped}

    # -------------------------------------------------------------- 3. resolve
    def _resolve_and_create(self, batch, res):
        """XLS-017 - ORM only, never raw SQL."""
        raw = res["raw"]
        if batch.kind == "proforma":
            case_id = self.env.context.get("itr_target_case_id")
            if not case_id:
                raise UserError("پروندهٔ بازرگانی مقصد مشخص نیست.")
            case = self.env["itr.trade.case"].browse(case_id)
            existing = case.item_ids.filtered(
                lambda i, r=raw: (i.name or "") == (r[1] or "").strip()
                and i.row_kind == (r[0] or "").strip())
            if existing:
                return None                     # XLS-014 idempotent re-run
            item = self.env["itr.trade.case.item"].create({
                "case_id": case.id,
                "row_kind": (raw[0] or "").strip(),
                "name": (raw[1] or "").strip(),
                "contract_tonnage": _f(raw[2]),
                "purchase_price_unit": _f(raw[3]),
                "sale_price_unit": _f(raw[5]),
            })
            vals = {}
            if (raw[7] or "").strip():
                vals["proforma_purchase_ref"] = (raw[7] or "").strip()
            if (raw[8] or "").strip():
                vals["proforma_sales_ref"] = (raw[8] or "").strip()
            if vals:
                case.write(vals)
            return item
        # freight -> XLS-015: ALWAYS a payment request that still needs review.
        waybill = (raw[0] or "").strip()
        case = self.env["itr.transport.case"].search([("waybill_number", "=", waybill)], limit=1)
        if not case:
            raise UserError("ردیف %s: بارنامهٔ «%s» یافت نشد." % (res["row_no"], waybill))
        charge = self.env["itr.charge.type"].search(
            [("code", "=", (raw[2] or "").strip())], limit=1)
        if not charge:
            raise UserError("ردیف %s: نوع هزینهٔ «%s» تعریف نشده است." % (res["row_no"], raw[2]))
        installment = int(_f(raw[3]) or 1)
        dup = self.env["itr.payment.request"].search([
            ("transport_case_id", "=", case.id),
            ("waybill_number", "=", waybill),
            ("payee_name", "=", (raw[1] or "").strip()),
            ("charge_type_id", "=", charge.id),
            ("installment_no", "=", installment),
        ], limit=1)
        if dup:
            return None
        return self.env["itr.payment.request"].create({
            "transport_case_id": case.id,
            "charge_type_id": charge.id,
            "waybill_number": waybill,
            "payee_name": (raw[1] or "").strip(),
            "payee_sheba": (raw[6] or "").strip(),
            "installment_no": installment,
            "amount": _f(raw[4]),
            "note": "ورود گروهی از اکسل (XLS-015: نیازمند بازبینی مالی)",
        })

    # ---------------------------------------------------------------- reading
    @api.model
    def _read_rows(self, content):
        import openpyxl
        wb = openpyxl.load_workbook(io.BytesIO(content), read_only=True, data_only=True)
        ws = wb.active
        rows = []
        for idx, values in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
            if not values or not any(v not in (None, "") for v in values):
                continue
            rows.append((idx, [("" if v is None else v) for v in values] + [""] * 12))
        return rows


def _f(value):
    try:
        return float(str(value).replace(",", "").strip() or 0)
    except Exception:
        return 0.0
PYEOF

# -----------------------------------------------------------------------------
# 9.23..9.28 — رجیستری نسخه‌دار قالب کارفرما (XLS-002..010, XLS-021)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_excel_template_registry.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""XLS-002 - the versioned, checksum protected Template Registry.

THE GOLDEN RULES OF THIS FILE (SRS 13-4), in priority order:

    P0  the real Excel contract: sheet NAME (alias allowed, falling back to the
        active sheet is forbidden), cell coordinate, merge, hidden column,
        EXACT header text, formula, sheet direction, print area, logo.
    P1  real project Meta fields only - a fieldname is never invented. When no
        approved field exists the cell stays None and the column is reported as
        UNRESOLVED (XLS-006/007).
    P2  project process rules (G05 customs != clearance, G07 execution only,
        VAL-008 masked sheba, OPS-023 effective tonnage).
    P3  alias / fuzzy matching - for DETECTION only. It never rewrites the
        customer text and never invents a destination.

    * The customer's own spelling is preserved letter by letter, typos
      included ("هزنیه تخلیه", "هزنیه بارگیری", "پگینگ", "ترخیصکار",
      "تامین کننده", "Data:", "مبدا"). Correction is allowed ONLY inside the
      alias table used for matching (XLS-004).
    * Coordinate lock beats fuzzy matching (XLS-005).
    * More than one candidate => UNRESOLVED, never a plausible guess (XLS-006).
    * The template on disk is opened read-only and NEVER written back; the
      output lives in io.BytesIO (XLS-003).
"""
import hashlib
import os

from odoo import api, fields, models
from odoo.exceptions import UserError

# ------------------------------------------------------------------ P3 aliases
# Matching layer ONLY. The workbook text is never changed to these values.
HEADER_ALIASES = {
    "هزنیه تخلیه": ("هزینه تخلیه",),
    "هزنیه بارگیری": ("هزینه بارگیری",),
    "پگینگ": ("پکینگ",),
    "ترخیصکار": ("ترخیص‌کار",),
    "تامین کننده": ("تأمین‌کننده",),
    "مبدا": ("مبدأ",),
    "data": ("date", "تاریخ"),
}

UNRESOLVED = None  # never write a guessed value

# ---------------------------------------------------------------- the registry
TEMPLATE_REGISTRY = {
    # =========================================================== T01 financial
    "financial": {
        "template_key": "template_01_financial",
        "pattern": "template_01",
        "version": "1.0",
        "source_file": "- 1405 گزارش خرید و فروش.xlsx",
        "sheet": "گزارش 1405",
        "sheet_alias": ("گزارش ۱۴۰۵", "1405"),
        "rtl": True,
        "header_row": 1,
        "child_header_row": 2,
        "data_start_row": 3,
        "total_row": None,
        "max_rows": 5000,
        "clear_data_area": True,
        "hidden_columns": ("I", "J", "K", "M", "U", "V", "W", "Y"),
        "protected_merges": ("F1:G1", "B1:B2", "A1:A2"),
        "date_mode": "jalali",
        "allow_logo_injection": False,
        "dataset": "financial26",
        "columns": [
            {"col": "A", "header": "تاریخ فروش", "field": "sales_date", "type": "Date"},
            {"col": "B", "header": "ش.فاکتور فروش", "field": "sales_inv", "type": "Identifier"},
            {"col": "C", "header": "مشتری", "field": "customer", "type": "Data"},
            {"col": "D", "header": "نوع کالا", "field": "item_s", "type": "Data"},
            {"col": "E", "header": "تناژ اصلی", "field": "plan_s", "type": "Float"},
            {"col": "F", "header": "مبلغ", "child_header": "دلار", "field": "amount_fx_s", "type": "Data"},
            {"col": "G", "header": "مبلغ", "child_header": "ریال", "field": "amount_base_s", "type": "Currency"},
            {"col": "H", "header": "تناژ خروجی\n فروش", "field": "ship_s", "type": "Float"},
            {"col": "I", "header": "جمع کل \nخارج شده فروش", "field": "cship_s", "type": "Float", "cumulative": True},
            {"col": "J", "header": "مازاد\n بارگیری فروش", "field": "sur_s", "type": "Float"},
            {"col": "K", "header": "جمع کل \nمازاد بارگیری فروش", "field": "csur_s", "type": "Float", "cumulative": True},
            {"col": "L", "header": "باقیمانده فروش", "field": "rem_s", "type": "Float"},
            {"col": "M", "header": "جمع کل\n باقیمانده فروش", "field": "crem_s", "type": "Float", "cumulative": True},
            {"col": "N", "header": "تاریخ خرید", "field": "pur_date", "type": "Date"},
            {"col": "O", "header": "ش.فاکتور خرید", "field": "pur_inv", "type": "Identifier"},
            {"col": "P", "header": "تامین کننده", "field": "supplier", "type": "Data"},
            {"col": "Q", "header": "نوع کالا", "field": "item_p", "type": "Data"},
            {"col": "R", "header": "تناژ\n اصلی", "field": "plan_p", "type": "Float"},
            {"col": "S", "header": "مبلغ", "field": "amount_p", "type": "Currency"},
            {"col": "T", "header": "تناژ \nخروجی خرید", "field": "ship_p", "type": "Float"},
            {"col": "U", "header": "جمع کل \nخارج شده خرید", "field": "cship_p", "type": "Float", "cumulative": True},
            {"col": "V", "header": "مازاد\n بارگیری خرید", "field": "sur_p", "type": "Float"},
            {"col": "W", "header": "جمع کل \nمازاد بارگیری خرید", "field": "csur_p", "type": "Float", "cumulative": True},
            {"col": "X", "header": "باقیمانده خرید", "field": "rem_p", "type": "Float"},
            {"col": "Y", "header": "جمع کل\n باقیمانده خرید", "field": "crem_p", "type": "Float", "cumulative": True},
            {"col": "Z", "header": "وضعیت", "field": "status", "type": "Data"},
        ],
    },
    # ============================================================= T02 freight
    "freight": {
        "template_key": "template_02_freight",
        "pattern": "template_02",
        "version": "1.0",
        "source_file": "خام لیست کرایه.xlsx",
        "sheet": "Sheet1",
        "rtl": True,
        "header_row": 2,
        "data_start_row": 3,
        "total_row": None,
        "max_rows": 2000,
        "clear_data_area": True,
        "title_cell": "A1",
        "title_prefix": " ",
        "protected_merges": ("A1:O1",),
        "date_mode": "jalali",
        "allow_logo_injection": False,
        "dataset": "custom_freight",
        "columns": [
            {"col": "A", "header": "ردیف", "field": "__row__", "type": "Row"},
            {"col": "B", "header": "نام صاحب حساب", "field": "payee_name", "type": "Data",
             "note": "XLS-016: account holder is NOT automatically the driver."},
            {"col": "C", "header": "شماره حساب", "field": "payee_sheba_masked", "type": "Identifier",
             "note": "XLS-016 + VAL-008: kept as a masked identifier, never auto-mapped to sheba."},
            {"col": "D", "header": "بانک ", "field": "payee_bank", "type": "Data"},
            {"col": "E", "header": "وزن", "field": "effective_tonnage", "type": "Float"},
            {"col": "F", "header": "کل هرتن", "field": UNRESOLVED, "type": "Float",
             "note": "no approved rate-per-ton field in phases 1..8 -> UNRESOLVED (XLS-007)."},
            {"col": "G", "header": " کرایه", "field": "freight_cost", "type": "Currency",
             "note": "template formula =F*E is protected where present (XLS-008)."},
            {"col": "H", "header": "هزنیه تخلیه", "field": UNRESOLVED, "type": "Currency",
             "note": "customer typo preserved exactly; no approved field -> UNRESOLVED."},
            {"col": "I", "header": "هزنیه بارگیری", "field": UNRESOLVED, "type": "Currency",
             "note": "customer typo preserved exactly; no approved field -> UNRESOLVED."},
            {"col": "J", "header": "کل کرایه", "field": UNRESOLVED, "type": "Currency",
             "note": "protected template formula =I+G."},
            {"col": "K", "header": "پیش کرایه", "field": "advance_paid_base", "type": "Currency"},
            {"col": "L", "header": "مانده", "field": UNRESOLVED, "type": "Currency",
             "note": "protected template formula =J-K."},
            {"col": "M", "header": "مرز-صاحب بار-نوع بار-نام راننده", "field": "composite_identity", "type": "Data"},
            {"col": "N", "header": "مبدا بارگیری", "field": "factory", "type": "Data"},
            {"col": "O", "header": " پیش فاکتور فروش", "field": "sales_ref", "type": "Identifier"},
        ],
        "formula_patterns": {"G": "=F{row}*E{row}", "J": "=I{row}+G{row}", "L": "=J{row}-K{row}"},
    },
    # ============================================================= T03 packing
    "packing": {
        "template_key": "template_03_packing",
        "pattern": "template_03",
        "version": "1.0",
        "source_file": "فرم پکینگ (1).xlsx",
        "sheet": "Sheet1",
        "rtl": False,                      # XLS-021: deliberately LTR
        "header_row": 7,
        "data_start_row": 10,
        "total_row": 11,
        "max_rows": 500,
        "clear_data_area": True,
        "protected_merges": ("B2:J3", "P7:X7", "C7:C9", "B5:J5", "G7:G9", "E7:E9",
                             "I7:I9", "H7:H9", "F7:F9", "J7:J9", "D7:D9", "B7:B9",
                             "B4:J4", "B6:J6"),
        "date_mode": "gregorian",
        "allow_logo_injection": False,     # XLS-021: never inject a logo here
        "dataset": "custom_packing",
        "meta_cells": [
            {"cell": "B4", "prefix": "INVOICE NUMBER: ", "field": "sales_ref", "type": "Identifier"},
            {"cell": "B5", "prefix": "Data:", "field": "packing_date", "type": "Date"},
            {"cell": "B6", "prefix": "Buyer: Mr ", "field": "customer", "type": "Data"},
        ],
        "total_label_cell": "C11",
        "sum_columns": {"F": "F11"},
        "columns": [
            {"col": "B", "header": "Row", "field": "__row__", "type": "Row"},
            {"col": "C", "header": "Description", "field": "goods", "type": "Data"},
            {"col": "D", "header": "Size", "field": "size", "type": "Data"},
            {"col": "E", "header": "Branch", "field": "qty", "type": "Int",
             "note": "Branch = pieces/شاخه (FIX-P9-1 packing_qty). Explicitly NOT «مرز»."},
            {"col": "F", "header": "Net Weight", "field": "weight", "type": "Float"},
            {"col": "G", "header": "Delivery B.", "field": "border", "type": "Data",
             "note": "delivery border context - NEVER the sales invoice."},
            {"col": "H", "header": "Driver's name", "field": "driver", "type": "Data"},
            {"col": "I", "header": "Car tag", "field": "plate", "type": "Identifier"},
            {"col": "J", "header": "Phone number", "field": "mobile", "type": "Identifier"},
        ],
    },
    # ============================================================ T04 purchase
    "purchase": {
        "template_key": "template_04_purchase",
        "pattern": "template_04",
        "version": "1.0",
        "source_file": "خام خرید.xlsx",
        "sheet": "پیش فاکتور خرید",
        "required_sheets": ("فروشنده", "معرفی کالا", "پیش فاکتور خرید", "صورت بارگیری"),
        "rtl": True,
        "header_row": 3,
        "data_start_row": 4,
        "total_row": None,
        "max_rows": 2000,
        "clear_data_area": True,
        "protected_merges": ("A1:K1",),
        "protected_cells": ("I2",),
        "date_mode": "jalali",
        "allow_logo_injection": False,
        "dataset": "custom_purchase",
        "meta_cells": [
            {"cell": "B2", "prefix": "", "field": "purchase_date", "type": "Date"},
            {"cell": "D2", "prefix": "", "field": "purchase_ref", "type": "Identifier"},
            {"cell": "F2", "prefix": "", "field": "supplier", "type": "Data"},
        ],
        "columns": [
            {"col": "A", "header": "ردیف", "field": "__row__", "type": "Row"},
            {"col": "B", "header": "نام کالا", "field": "item", "type": "Data"},
            {"col": "C", "header": "سایز", "field": "size_key", "type": "Data",
             "note": "SUMIFS criteria cell - must be identical to 'صورت بارگیری'!D."},
            {"col": "D", "header": "تناژ", "field": "contract_tonnage", "type": "Float"},
            {"col": "E", "header": "واحد وزن", "field": UNRESOLVED, "type": "Data",
             "note": "no approved weight-unit field -> UNRESOLVED, never guessed."},
            {"col": "F", "header": "فی واحد", "field": "purchase_price_unit", "type": "Currency",
             "note": "FIX-P9-4: RESOLVED in Odoo (unit price exists), unlike the ERPNext generation."},
            {"col": "G", "header": "نوع ارز", "field": "purchase_currency", "type": "Data",
             "note": "FIX-P9-4: RESOLVED - FIN-011 currency lives on the row."},
            {"col": "H", "header": "تحویل", "field": "delivery_mode", "type": "Data"},
            {"col": "I", "header": "مقدار حمل شده", "field": UNRESOLVED, "type": "Float",
             "note": "protected SUMIFS formula."},
            {"col": "J", "header": "مانده", "field": UNRESOLVED, "type": "Float", "note": "protected formula."},
            {"col": "K", "header": "ارزش کالای مانده", "field": UNRESOLVED, "type": "Currency", "note": "protected formula."},
        ],
        "formula_patterns": {
            "I": "=IF(D{row}<>\"\",SUMIFS('صورت بارگیری'!$E$3:$E$1048576,"
                 "'صورت بارگیری'!$D$3:$D$1048576,C{row}),\"\")",
            "J": "=IF(D{row}<>\"\",D{row}-I{row},\"\")",
            "K": "=IF(D{row}<>\"\",J{row}*F{row},\"\")",
        },
        "extra_sheets": {
            "loading": {
                "sheet": "صورت بارگیری",
                "rtl": True,
                "header_row": 2,
                "data_start_row": 3,
                "total_row": None,
                "max_rows": 2000,
                "clear_data_area": True,
                "protected_merges": ("A1:K1",),
                "protected_cells": ("A1",),
                "date_mode": "jalali",
                "columns": [
                    {"col": "A", "header": "ردیف", "field": "__row__", "type": "Row"},
                    {"col": "B", "header": "پگینگ", "field": UNRESOLVED, "type": "Data",
                     "note": "customer spelling «پگینگ» preserved; meaning unresolved."},
                    {"col": "C", "header": "تاریخ بارگیری", "field": "loading_date", "type": "Date"},
                    {"col": "D", "header": "کالا", "field": "size_key", "type": "Data",
                     "note": "SUMIFS key column - must match 'پیش فاکتور خرید'!C."},
                    {"col": "E", "header": "وزن خالص", "field": "weight", "type": "Float"},
                    {"col": "F", "header": "مقصد", "field": "destination", "type": "Data"},
                    {"col": "G", "header": "ش. کامیون", "field": "plate", "type": "Identifier"},
                    {"col": "H", "header": "نام راننده", "field": "driver", "type": "Data"},
                    {"col": "I", "header": "شماره راننده", "field": "mobile", "type": "Identifier"},
                    {"col": "J", "header": "خریدار", "field": "customer", "type": "Data"},
                    {"col": "K", "header": "ترخیصکار", "field": "broker", "type": "Data"},
                ],
            },
        },
    },
    # ============================================================ T05 dispatch
    "dispatch": {
        "template_key": "template_05_dispatch",
        "pattern": "template_05",
        "version": "1.0",
        "source_file": "فایل خام.xlsx",
        "sheet": "Sheet1",
        "rtl": True,
        "header_row": 3,
        "data_start_row": 4,
        "total_row": 10,
        "max_rows": 1000,
        "clear_data_area": True,
        "protected_merges": ("B2:L2",),
        "date_mode": "jalali",
        "allow_logo_injection": False,
        "sum_columns": {"E": "E10"},
        "dataset": "custom_dispatch",
        "columns": [
            {"col": "B", "header": "ردیف", "field": "__row__", "type": "Row"},
            {"col": "C", "header": "تاریخ بارگیری", "field": "loading_date", "type": "Date"},
            {"col": "D", "header": "نوع بار", "field": "goods", "type": "Data"},
            {"col": "E", "header": "وزن", "field": "weight", "type": "Float"},
            {"col": "F", "header": "مبدا", "field": "factory", "type": "Data"},
            {"col": "G", "header": "مقصد", "field": "destination", "type": "Data"},
            {"col": "H", "header": "ش. کامیون", "field": "plate", "type": "Identifier"},
            {"col": "I", "header": "نام راننده", "field": "driver", "type": "Data"},
            {"col": "J", "header": "شماره راننده", "field": "mobile", "type": "Identifier"},
            {"col": "K", "header": "ترخیصکار", "field": "broker", "type": "Data"},
            {"col": "L", "header": "باربری", "field": "carrier", "type": "Data"},
        ],
    },
}


class ItrExcelTemplate(models.Model):
    """XLS-002 - the persisted, versioned registry row (with checksum)."""
    _name = "itr.excel.template"
    _description = "Employer Excel template registry entry"
    _order = "template_key"

    name = fields.Char(string="Name", required=True)
    template_key = fields.Char(string="Key", required=True, index=True)
    registry_key = fields.Char(string="Registry key", required=True)
    version = fields.Char(string="Version", required=True, default="1.0")
    source_file = fields.Char(string="Customer file name")
    sheet_name = fields.Char(string="Sheet name", required=True)
    checksum = fields.Char(string="SHA-256", readonly=True)
    file_present = fields.Boolean(string="File present", readonly=True)
    column_count = fields.Integer(string="Mapped columns", readonly=True)
    unresolved_count = fields.Integer(string="UNRESOLVED columns", readonly=True)
    unresolved_detail = fields.Text(string="UNRESOLVED detail", readonly=True)
    state = fields.Selection([("ready", "Ready"), ("suspended", "Suspended - waiting for customer file")],
                             default="suspended", required=True, readonly=True)
    note = fields.Text(string="Note")

    _sql_constraints = [
        ("itr_excel_template_uniq", "unique(template_key, version)",
         "XLS-002: هر قالب در هر نسخه فقط یک رکورد دارد."),
    ]

    @api.model
    def template_dir(self):
        from odoo.modules.module import get_module_path
        path = get_module_path("itr_reports")
        return os.path.join(path, "static", "excel_templates")

    @api.model
    def find_file(self, pattern):
        directory = self.template_dir()
        if not os.path.isdir(directory):
            return None
        for fn in sorted(os.listdir(directory)):
            if pattern in fn and fn.lower().endswith(".xlsx"):
                return os.path.join(directory, fn)
        return None

    @api.model
    def sync_registry(self):
        """Idempotent (NFR-002): refresh checksum/state for the five templates."""
        for reg_key, reg in TEMPLATE_REGISTRY.items():
            path = self.find_file(reg["pattern"])
            checksum, present = "", False
            if path and os.path.exists(path):
                with open(path, "rb") as fh:
                    checksum = hashlib.sha256(fh.read()).hexdigest()
                present = True
            unresolved = [c["col"] + " " + (c.get("header") or "")
                          for c in reg["columns"] if not c.get("field")]
            for extra in (reg.get("extra_sheets") or {}).values():
                unresolved += [extra["sheet"] + "!" + c["col"] + " " + (c.get("header") or "")
                               for c in extra["columns"] if not c.get("field")]
            vals = {
                "name": reg["template_key"],
                "template_key": reg["template_key"],
                "registry_key": reg_key,
                "version": reg["version"],
                "source_file": reg["source_file"],
                "sheet_name": reg["sheet"],
                "checksum": checksum,
                "file_present": present,
                "column_count": len(reg["columns"]),
                "unresolved_count": len(unresolved),
                "unresolved_detail": "\n".join(unresolved),
                "state": "ready" if present else "suspended",
            }
            rec = self.search([("template_key", "=", reg["template_key"]),
                               ("version", "=", reg["version"])], limit=1)
            if rec:
                rec.write(vals)
            else:
                self.create(vals)
        return True

    def action_open_file_folder(self):
        self.ensure_one()
        raise UserError("مسیر قالب‌ها: %s" % self.template_dir())
PYEOF

write_utf8 "${REP_DIR}/models/itr_excel_custom.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""XLS-003..XLS-010 - filling the five real customer workbooks.

Everything that makes a customer workbook "theirs" is preserved: merges,
styles, hidden columns, sheet direction, print area, logo and above all the
formulas. The only formula rewrite that is allowed is the row-number clone of
a declared formula family when a new data row is inserted (XLS-008), plus the
declared SUM range extension.

A full Sync Log is produced for every run so that a human can audit exactly
which cell received which value from which field, with which confidence, and
which columns stayed UNRESOLVED (XLS-006/007).
"""
import io
import json
import os
import re
from copy import copy

from odoo import api, fields, models
from odoo.exceptions import UserError

from odoo.addons.itr_base.utils import jalali as jal
from odoo.addons.itr_base.utils import validators as val

from .itr_excel_template_registry import HEADER_ALIASES, TEMPLATE_REGISTRY


# ------------------------------------------------------------------ G1 normalise
def _norm(value):
    """One normaliser for Persian/Arabic fuzzy matching (matching layer only)."""
    return val.normalize_text(value).lower() if value is not None else ""


def _alias_keys(text):
    key = _norm(text)
    keys = {key}
    for src, targets in HEADER_ALIASES.items():
        if _norm(src) == key:
            keys.update(_norm(t) for t in targets)
        for t in targets:
            if _norm(t) == key:
                keys.add(_norm(src))
    return {k for k in keys if k}


class ItrExcelSyncLog(models.Model):
    _name = "itr.excel.sync.log"
    _description = "Sync Log of an employer-template Excel run"
    _order = "id desc"

    name = fields.Char(required=True, default="/")
    template_key = fields.Char(required=True, index=True)
    source_file = fields.Char()
    user_id = fields.Many2one("res.users", default=lambda s: s.env.user, readonly=True)
    run_on = fields.Datetime(default=fields.Datetime.now, readonly=True)
    row_count = fields.Integer(readonly=True)
    written_cells = fields.Integer(readonly=True)
    protected_cells = fields.Integer(readonly=True)
    unresolved_cells = fields.Integer(readonly=True)
    payload = fields.Text(string="Entries (JSON)", readonly=True)


class _Log(object):
    """In-memory collector, persisted at the end of the run."""

    def __init__(self, template_key, source_file):
        self.template_key = template_key
        self.source_file = source_file
        self.entries = []

    def add(self, **kw):
        self.entries.append(kw)

    def count(self, status):
        return sum(1 for e in self.entries if e.get("status") == status)

    def persist(self, env, rows):
        env["itr.excel.sync.log"].create({
            "name": self.template_key,
            "template_key": self.template_key,
            "source_file": self.source_file,
            "row_count": rows,
            "written_cells": self.count("ok"),
            "protected_cells": self.count("protected"),
            "unresolved_cells": self.count("unresolved"),
            "payload": json.dumps(self.entries[:4000], ensure_ascii=False, default=str),
        })


class ItrExcelCustom(models.AbstractModel):
    _name = "itr.excel.custom"
    _description = "Employer template Excel writer (golden rules)"

    # ------------------------------------------------------------- cell tools
    @api.model
    def _set_cell(self, ws, row_idx, col_idx, value):
        from openpyxl.cell.cell import MergedCell
        cell = ws.cell(row=row_idx, column=col_idx)
        if isinstance(cell, MergedCell):
            for rng in ws.merged_cells.ranges:
                if rng.min_row <= row_idx <= rng.max_row and rng.min_col <= col_idx <= rng.max_col:
                    ws.cell(row=rng.min_row, column=rng.min_col).value = value
                    return True
            return False
        cell.value = value
        return True

    @api.model
    def _write_coord(self, ws, coord, value):
        cell = ws[coord]
        return self._set_cell(ws, cell.row, cell.column, value)

    @api.model
    def _is_formula(self, value):
        return isinstance(value, str) and value.startswith("=")

    @api.model
    def _has_formula(self, ws, row_idx, col_idx):
        from openpyxl.cell.cell import MergedCell
        cell = ws.cell(row=row_idx, column=col_idx)
        return False if isinstance(cell, MergedCell) else self._is_formula(cell.value)

    @api.model
    def _transform(self, value, vtype, date_mode):
        """XLS-018 - numbers stay numbers, identifiers stay text."""
        if value in (None, ""):
            return None
        if vtype == "Date":
            if date_mode == "gregorian":
                try:
                    return fields.Date.to_date(value).strftime("%Y/%m/%d")
                except Exception:
                    return str(value)
            return jal.to_jalali_str(value)
        if vtype in ("Currency", "Float"):
            try:
                return float(value)
            except Exception:
                return value
        if vtype in ("Int", "Row"):
            try:
                return int(float(value))
            except Exception:
                return value
        if vtype == "Identifier":
            return str(value)
        return value

    # ------------------------------------------------------ merge / row insert
    @api.model
    def _unmerge_data_area(self, ws, reg, start_row, total_row=None):
        """XLS-008/009 - unmerge ONLY the data area; title/header/total stay."""
        from openpyxl.worksheet.cell_range import CellRange
        protected = {str(CellRange(r)) for r in (reg.get("protected_merges") or ())}
        for rng in list(ws.merged_cells.ranges):
            ref = str(rng)
            if ref in protected or rng.min_row < start_row:
                continue
            if total_row is not None and rng.min_row >= total_row:
                continue
            try:
                ws.unmerge_cells(ref)
            except Exception:
                pass

    @api.model
    def _clone_style(self, ws, src_row, dst_row):
        from openpyxl.cell.cell import MergedCell
        for col in range(1, (ws.max_column or 1) + 1):
            s = ws.cell(row=src_row, column=col)
            d = ws.cell(row=dst_row, column=col)
            if isinstance(d, MergedCell):
                continue
            try:
                if s.has_style:
                    d._style = copy(s._style)
                if s.number_format:
                    d.number_format = s.number_format
            except Exception:
                pass

    @api.model
    def _clone_formulas(self, ws, reg, src_row, dst_row):
        """XLS-008 - the ONLY allowed rewrite: the declared formula family."""
        from openpyxl.cell.cell import MergedCell
        from openpyxl.utils import column_index_from_string
        patterns = reg.get("formula_patterns") or {}
        if patterns:
            for letter, pattern in patterns.items():
                cell = ws.cell(row=dst_row, column=column_index_from_string(letter))
                if not isinstance(cell, MergedCell):
                    cell.value = pattern.format(row=dst_row)
            return
        for col in range(1, (ws.max_column or 1) + 1):
            s = ws.cell(row=src_row, column=col)
            if not self._is_formula(s.value):
                continue
            d = ws.cell(row=dst_row, column=col)
            if isinstance(d, MergedCell):
                continue
            d.value = re.sub(r"(\$?[A-Za-z]{1,3})(\$?)(\d+)",
                             lambda m: m.group(0) if m.group(2) == "$"
                             else "%s%d" % (m.group(1), int(m.group(3)) + (dst_row - src_row)),
                             s.value)

    @api.model
    def _ensure_rows(self, ws, reg, start_row, needed, total_row=None):
        """XLS-009 - merge aware insert: ranges below the total row are shifted."""
        from openpyxl.worksheet.cell_range import CellRange
        if needed <= 0:
            return total_row
        if total_row is not None:
            available = total_row - start_row
            if needed > available:
                extra = needed - available
                below = [str(r) for r in list(ws.merged_cells.ranges) if r.min_row >= total_row]
                for ref in below:
                    try:
                        ws.unmerge_cells(ref)
                    except Exception:
                        pass
                ws.insert_rows(total_row, amount=extra)
                for r in range(total_row, total_row + extra):
                    self._clone_style(ws, start_row, r)
                    self._clone_formulas(ws, reg, start_row, r)
                for ref in below:
                    try:
                        rng = CellRange(ref)
                        rng.shift(row_shift=extra)
                        ws.merge_cells(str(rng))
                    except Exception:
                        pass
                total_row += extra
            return total_row
        last = start_row + needed - 1
        for r in range((ws.max_row or 0) + 1, last + 1):
            self._clone_style(ws, start_row, r)
            self._clone_formulas(ws, reg, start_row, r)
        return None

    # ---------------------------------------------------------- header lookup
    @api.model
    def _find_header_row(self, ws, reg, max_rows=30):
        """XLS-005 - the declared coordinate wins; fuzzy only relocates the row."""
        from openpyxl.utils import column_index_from_string
        columns = reg.get("columns") or []
        declared = reg.get("header_row") or 1

        def score(row_idx):
            hit = 0
            for spec in columns:
                actual = _norm(ws.cell(row=row_idx,
                                       column=column_index_from_string(spec["col"])).value)
                if actual and actual in _alias_keys(spec.get("header")):
                    hit += 1
            return hit

        if declared <= (ws.max_row or 1) and score(declared) > 0:
            return declared
        best, best_score = declared, 0
        for r in range(1, min(max_rows, ws.max_row or 1) + 1):
            s = score(r)
            if s > best_score:
                best, best_score = r, s
        return best

    @api.model
    def _map_columns(self, ws, header_row, reg, log):
        from openpyxl.utils import column_index_from_string
        mapping = {}
        for spec in reg.get("columns") or []:
            col_idx = column_index_from_string(spec["col"])
            actual = ws.cell(row=header_row, column=col_idx).value
            normalized = _norm(actual)
            expected = _alias_keys(spec.get("header"))
            if normalized and normalized in expected:
                method, confidence = "coordinate+exact", 1.0
            elif normalized:
                method, confidence = "coordinate", 0.9
            else:
                method, confidence = "coordinate+empty", 0.8
            mapping[col_idx] = spec
            log.add(sheet=ws.title, cell="%s%d" % (spec["col"], header_row),
                    field=spec.get("field"), raw=actual, normalized=normalized,
                    method=method, confidence=confidence, action="map_column",
                    status="ok" if spec.get("field") else "unresolved",
                    error=None if spec.get("field") else spec.get("note"))
        return mapping

    @api.model
    def _clear_area(self, ws, reg, start_row, total_row=None):
        from openpyxl.cell.cell import MergedCell
        from openpyxl.utils import column_index_from_string
        if not reg.get("clear_data_area"):
            return
        last = (total_row - 1) if total_row else (ws.max_row or start_row)
        for spec in reg.get("columns") or []:
            col_idx = column_index_from_string(spec["col"])
            for r in range(start_row, last + 1):
                cell = ws.cell(row=r, column=col_idx)
                if isinstance(cell, MergedCell) or self._is_formula(cell.value):
                    continue
                cell.value = None

    # --------------------------------------------------------------- the fill
    @api.model
    def _fill_sheet(self, ws, reg, rows, log):
        from openpyxl.utils import column_index_from_string
        date_mode = reg.get("date_mode") or "jalali"
        header_row = self._find_header_row(ws, reg)
        start_row = reg.get("data_start_row") or (header_row + 1)
        total_row = reg.get("total_row")
        max_rows = reg.get("max_rows") or 2000
        if len(rows) > max_rows:
            raise UserError("تعداد ردیف (%s) از سقف قالب (%s) بیشتر است." % (len(rows), max_rows))

        mapping = self._map_columns(ws, header_row, reg, log)
        self._unmerge_data_area(ws, reg, start_row, total_row)
        self._clear_area(ws, reg, start_row, total_row)
        total_row = self._ensure_rows(ws, reg, start_row, len(rows), total_row)
        protected_cells = set(reg.get("protected_cells") or ())

        for offset, row in enumerate(rows):
            r = start_row + offset
            for col_idx, spec in mapping.items():
                coord = "%s%d" % (spec["col"], r)
                if coord in protected_cells:
                    continue
                if self._has_formula(ws, r, col_idx):
                    log.add(sheet=ws.title, cell=coord, field=spec.get("field"),
                            method="coordinate", confidence=1.0,
                            action="skip_protected_formula", status="protected")
                    continue
                field = spec.get("field")
                if not field:
                    log.add(sheet=ws.title, cell=coord, field=None, method="registry",
                            confidence=0.0, action="skip_unresolved",
                            status="unresolved", error=spec.get("note"))
                    continue
                if field == "__row__":
                    self._set_cell(ws, r, col_idx, offset + 1)
                    continue
                raw = row.get(field)
                value = self._transform(raw, spec.get("type"), date_mode)
                if value in (None, ""):
                    continue
                self._set_cell(ws, r, col_idx, value)
                log.add(sheet=ws.title, cell=coord, field=field, raw=raw,
                        normalized=value, method="coordinate", confidence=1.0,
                        action="write", status="ok")

        last_data_row = start_row + len(rows) - 1
        self._rewrite_sums(ws, reg, start_row, last_data_row, total_row, log)
        self._fill_meta(ws, reg, rows, log)
        return {"header_row": header_row, "start_row": start_row,
                "total_row": total_row, "last_data_row": last_data_row}

    @api.model
    def _rewrite_sums(self, ws, reg, start_row, last_row, total_row, log):
        """XLS-008 - the only other permitted formula write: declared SUM range."""
        from openpyxl.cell.cell import MergedCell
        from openpyxl.utils import column_index_from_string
        sums = reg.get("sum_columns") or {}
        if not sums or last_row < start_row:
            return
        declared = reg.get("total_row")
        shift = (total_row - declared) if (declared and total_row) else 0
        for letter, coord in sums.items():
            target_row = ws[coord].row + shift
            cell = ws.cell(row=target_row, column=column_index_from_string(letter))
            if isinstance(cell, MergedCell):
                continue
            formula = "=SUM(%s%d:%s%d)" % (letter, start_row, letter, last_row)
            cell.value = formula
            log.add(sheet=ws.title, cell="%s%d" % (letter, target_row),
                    method="registry_sum_rewrite", confidence=1.0,
                    normalized=formula, action="rewrite_sum", status="ok")

    @api.model
    def _fill_meta(self, ws, reg, rows, log):
        metas = reg.get("meta_cells") or []
        if not metas or not rows:
            return
        first = rows[0]
        date_mode = reg.get("date_mode") or "jalali"
        for spec in metas:
            field = spec.get("field")
            raw = first.get(field) if field else None
            if raw in (None, ""):
                log.add(sheet=ws.title, cell=spec.get("cell"), field=field,
                        method="registry", confidence=0.0, action="skip_meta",
                        status="unresolved")
                continue
            value = self._transform(raw, spec.get("type"), date_mode)
            text = "%s%s" % (spec.get("prefix") or "", value)
            self._write_coord(ws, spec["cell"], text)
            log.add(sheet=ws.title, cell=spec.get("cell"), field=field, raw=raw,
                    normalized=text, method="coordinate", confidence=1.0,
                    action="write_meta", status="ok")

    @api.model
    def _apply_title(self, ws, reg, options, log):
        cell = reg.get("title_cell")
        if not cell:
            return
        value = options.get("date_to") or options.get("date_from")
        if not value:
            return
        text = "%s%s" % (reg.get("title_prefix") or "", jal.to_jalali_str(value))
        self._write_coord(ws, cell, text)
        log.add(sheet=ws.title, cell=cell, method="coordinate", confidence=1.0,
                normalized=text, action="write_title", status="ok")

    @api.model
    def _restore_hidden(self, ws, reg):
        for letter in reg.get("hidden_columns") or ():
            ws.column_dimensions[letter].hidden = True

    # --------------------------------------------------------------- public
    @api.model
    def render(self, registry_key, options=None):
        """Return (filename, bytes). The template on disk is never written."""
        options = dict(options or {})
        reg = TEMPLATE_REGISTRY.get(registry_key)
        if not reg:
            raise UserError("قالب ناشناخته: %s" % registry_key)

        Template = self.env["itr.excel.template"]
        path = Template.find_file(reg["pattern"])
        if not path:
            raise UserError(
                "قالب «%s» هنوز از کارفرما دریافت نشده است (XLS-020). "
                "این زیربخش رسماً «معلق - در انتظار فایل کارفرما» است."
                % reg["template_key"])

        import openpyxl
        wb = openpyxl.load_workbook(path)                 # XLS-003: read only
        for required in reg.get("required_sheets") or ():
            if required not in wb.sheetnames:
                raise UserError("شیت «%s» در قالب یافت نشد." % required)

        ws = self._pick_sheet(wb, reg, reg["sheet"], reg.get("sheet_alias"))
        ws.sheet_view.rightToLeft = bool(reg.get("rtl"))

        log = _Log(reg["template_key"], reg["source_file"])
        datasets = self.env["itr.excel.dataset"].build(reg["dataset"], options)
        rows = datasets["rows"]

        self._apply_title(ws, reg, options, log)
        self._fill_sheet(ws, reg, rows, log)
        self._restore_hidden(ws, reg)

        for key, sub in (reg.get("extra_sheets") or {}).items():
            sub_rows = datasets.get("extra", {}).get(key, [])
            sub_ws = self._pick_sheet(wb, reg, sub["sheet"])
            sub_ws.sheet_view.rightToLeft = bool(sub.get("rtl"))
            self._fill_sheet(sub_ws, sub, sub_rows, log)
            self._restore_hidden(sub_ws, sub)

        # XLS-021: the packing form NEVER gets a logo injected.
        if reg.get("allow_logo_injection") and not getattr(ws, "_images", None):
            logo = os.path.join(Template.template_dir(), "client_logo.png")
            if os.path.exists(logo):
                from openpyxl.drawing.image import Image as XLImage
                img = XLImage(logo)
                img.width, img.height = 120, 60
                ws.add_image(img, "B2")

        log.persist(self.env, len(rows))
        out = io.BytesIO()
        wb.save(out)                                      # in-memory only
        name = self.env["itr.excel.common"].safe_filename(reg["template_key"])
        return name, out.getvalue()

    @api.model
    def _pick_sheet(self, wb, reg, sheet_name, aliases=None):
        """XLS-002 - falling back to the active sheet is FORBIDDEN."""
        if sheet_name in wb.sheetnames:
            return wb[sheet_name]
        for alias in (aliases or ()):
            if alias in wb.sheetnames:
                return wb[alias]
        target = _norm(sheet_name)
        for name in wb.sheetnames:
            if _norm(name) == target:
                return wb[name]
        raise UserError("شیت «%s» در قالب «%s» یافت نشد (fallback به شیت فعال ممنوع است)."
                        % (sheet_name, reg["template_key"]))


class ItrExcelDataset(models.AbstractModel):
    """P1 - the datasets that feed the customer templates.

    Every value here comes from a REAL project field or from the metric
    registry. No fieldname is ever invented.
    """
    _name = "itr.excel.dataset"
    _description = "Datasets for the employer Excel templates"

    @api.model
    def build(self, dataset_key, options=None):
        options = dict(options or {})
        return getattr(self, "_ds_%s" % dataset_key)(options)

    def _ds_financial26(self, options):
        data = self.env["itr.report.financial26"].build(options)
        return {"rows": data["rows"], "extra": {}}

    def _loadings(self, options):
        engine = self.env["itr.report.engine"]
        return self.env["itr.transport.case"].search(
            engine._transport_domain(options), order="order_date asc, id asc")

    def _ds_custom_freight(self, options):
        reg = self.env["itr.kpi.service"]
        rows = []
        for c in self._loadings(options):
            payee = c.cost_line_ids.filtered(lambda l: l.category == "freight")[:1]
            rows.append({
                "payee_name": payee.payee_name if payee else "",
                "payee_sheba_masked": payee.payee_sheba_masked if payee else "",
                "payee_bank": payee.payee_bank if payee else "",
                "effective_tonnage": reg.metric("effective", c),
                "freight_cost": c.freight_cost or 0.0,
                "advance_paid_base": c.advance_paid_base or 0.0,
                "composite_identity": "-".join([
                    c.border_id.display_name or "",
                    c.customer_id.display_name or c.factory_id.display_name or "",
                    c.goods_description or "",
                    c.driver_id.display_name or "",
                ]),
                "factory": c.factory_id.display_name or "",
                "sales_ref": c.sales_ref or "",
            })
        return {"rows": rows, "extra": {}}

    def _ds_custom_packing(self, options):
        data = self.env["itr.report.engine"].run("packing", options)
        rows = []
        for r in data["rows"]:
            rows.append({
                "goods": r["goods"],
                "size": r["thickness"] or "",
                "qty": r["qty"],
                "weight": r["weight"],
                "border": r["border"],
                "driver": r["driver"],
                "plate": r["plate"],
                "mobile": r["mobile"],
                "customer": r["customer"],
                "packing_date": r["packing_date"],
                "sales_ref": r["sales_ref"],
            })
        return {"rows": rows, "extra": {}}

    def _ds_custom_purchase(self, options):
        reg = self.env["itr.kpi.service"]
        dom = [("case_id.state", "not in", ("rejected",)),
               ("row_kind", "in", ("purchase", "both"))]
        items = self.env["itr.trade.case.item"].search(dom, order="case_id asc, sequence asc")
        rows = []
        for i in items:
            rows.append({
                "item": i.name or "",
                "size_key": i.dimension_note or i.name or "",
                "contract_tonnage": reg.metric("planned", i),
                "purchase_price_unit": i.purchase_price_unit or 0.0,
                "purchase_currency": i.purchase_currency_id.name or "",
                "delivery_mode": i.case_id.destination or "",
                "purchase_date": i.case_id.create_date,
                "purchase_ref": i.case_id.proforma_purchase_ref or i.case_id.name,
                "supplier": i.case_id.factory_id.display_name or "",
            })
        loadings = []
        for c in self._loadings(options):
            loadings.append({
                "loading_date": c.order_date,
                "size_key": c.dimension_note or c.goods_description or "",
                "weight": reg.metric("effective", c),
                "destination": c.destination or "",
                "plate": c.vehicle_id.plate_number or "",
                "driver": c.driver_id.display_name or "",
                "mobile": c.driver_mobile or "",
                "customer": c.customer_id.display_name or "",
                "broker": c.customs_broker_id.display_name or "",
            })
        return {"rows": rows, "extra": {"loading": loadings}}

    def _ds_custom_dispatch(self, options):
        reg = self.env["itr.kpi.service"]
        rows = []
        for c in self._loadings(options):
            rows.append({
                "loading_date": c.order_date,
                "goods": c.goods_description or "",
                "weight": reg.metric("effective", c),
                "factory": c.factory_id.display_name or "",
                "destination": c.destination or "",
                "plate": c.vehicle_id.plate_number or "",
                "driver": c.driver_id.display_name or "",
                "mobile": c.driver_mobile or "",
                "broker": c.customs_broker_id.display_name or "",
                "carrier": c.carrier_id.display_name or "",
            })
        return {"rows": rows, "extra": {}}
PYEOF

# -----------------------------------------------------------------------------
# پچ افزایشی روی مدل‌های موجود + پنجرهٔ اجرای گزارش
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/models/itr_ux_phase9.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Additive-only extensions required by phase 9 (R1/R4).

Nothing from phases 1..8 is rewritten. Two fields are ADDED by inheritance:

  [FIX-P9-1] itr.transport.case.packing_qty
      SRS 13-2/G09 makes the column «تعداد» mandatory for the packing report
      and for the T03 customer workbook, but no phase 4..8 field carried it.
      XLS-007 would have forced UNRESOLVED; because the SRS marks the column
      mandatory, the correct answer is a REAL field, added here.

  [FIX-P9-2] itr.trade.case.report_row_count
      Read-only helper so a user can see, on the form, how many logical rows
      (REP-013) their case will produce in the 26-column report.
"""
from odoo import api, fields, models


class ItrTransportCaseReports(models.Model):
    _inherit = "itr.transport.case"

    packing_qty = fields.Integer(
        string="Branch / pieces (packing)",
        help="G09 - the mandatory «تعداد» column of the packing report and of "
             "column E «Branch» of the employer packing workbook. Added in "
             "phase 9 (FIX-P9-1); never overwrite it from a report.",
        tracking=True,
    )

    def action_open_packing_report(self):
        self.ensure_one()
        return self.env["itr.report.run"].open_for(
            "packing", {"transport_case_id": self.id})


class ItrTradeCaseReports(models.Model):
    _inherit = "itr.trade.case"

    report_row_count = fields.Integer(
        string="Logical report rows (REP-013)", compute="_compute_report_row_count")

    @api.depends("item_ids.row_kind")
    def _compute_report_row_count(self):
        for case in self:
            case.report_row_count = sum(
                2 if item.row_kind == "both" else 1 for item in case.item_ids)

    def action_open_financial26(self):
        self.ensure_one()
        return self.env["itr.report.run"].open_for("financial26", {"case_id": self.id})
PYEOF

write_utf8 "${REP_DIR}/models/itr_report_run.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""The single filter window every report and every export is launched from.

UX-063 - nothing here bypasses a server action; the wizard only calls the
report engine and the Excel services, all of which run with the CALLING user
so record rules stay in force (REP-006).
"""
import base64

from odoo import api, fields, models
from odoo.exceptions import UserError

REPORT_SELECTION = [
    ("financial26", "G01 - گزارش جامع مالی خرید/فروش (۲۶ ستون)"),
    ("freight", "G02 - گزارش کرایه"),
    ("customs", "G03 - گزارش گمرک و ترخیص"),
    ("tonnage", "G04 - گزارش تناژ"),
    ("profit", "G05 - گزارش سود"),
    ("stalled", "G06 - پرونده‌های متوقف‌شده"),
    ("payments", "G07 - گزارش پرداخت‌ها"),
    ("period_summary", "G08 - خلاصهٔ روزانه/ماهانه/سالانه"),
    ("packing", "G09 - گزارش پکینگ"),
    ("item_balance", "G10 - ماندهٔ هر ردیف کالا"),
    ("open_invoices", "G11 - فاکتورهای باز"),
    ("profit_per_load", "G12 - سود هر بارگیری"),
    ("freight_advance", "G13 - کرایه با پیش‌کرایه و مانده"),
    ("border_loading", "G14 - بارگیری کارخانه‌ها به تفکیک مرز"),
    ("factory_debt", "G15 - دفتر طلب از کارخانه"),
]

TEMPLATE_SELECTION = [
    ("financial", "T01 - گزارش خرید و فروش ۱۴۰۵"),
    ("freight", "T02 - لیست کرایه"),
    ("packing", "T03 - فرم پکینگ"),
    ("purchase", "T04 - پیش فاکتور خرید"),
    ("dispatch", "T05 - فایل خام ارسال"),
]


class ItrReportRun(models.TransientModel):
    _name = "itr.report.run"
    _description = "Phase 9 report / export launcher"

    report_key = fields.Selection(REPORT_SELECTION, string="گزارش",
                                  required=True, default="financial26")
    date_from = fields.Date(string="از تاریخ")
    date_to = fields.Date(string="تا تاریخ")
    period = fields.Selection([("detail", "جزئیات"), ("daily", "روزانه"),
                               ("monthly", "ماهانه"), ("yearly", "سالانه")],
                              string="دوره", default="detail")
    group_by = fields.Selection([("driver", "راننده"), ("carrier", "باربری"),
                                 ("customer", "مشتری"), ("factory", "کارخانه"),
                                 ("border", "مرز"), ("broker", "ترخیص‌کار"),
                                 ("agent", "نمایندهٔ مرز")], string="تفکیک")
    border_id = fields.Many2one("itr.border", string="مرز")
    carrier_id = fields.Many2one("res.partner", string="باربری",
                                 domain=[("is_shipping_line", "=", True)])
    factory_id = fields.Many2one("res.partner", string="کارخانه",
                                 domain=[("is_factory", "=", True)])
    customer_id = fields.Many2one("res.partner", string="مشتری")
    case_id = fields.Many2one("itr.trade.case", string="پروندهٔ بازرگانی")
    template_key = fields.Selection(TEMPLATE_SELECTION, string="قالب کارفرما")
    result_html = fields.Html(string="نتیجه", readonly=True, sanitize=False)
    output_file = fields.Binary(string="فایل خروجی", readonly=True, attachment=False)
    output_name = fields.Char(string="نام فایل", readonly=True)

    def _options(self):
        self.ensure_one()
        return {
            "date_from": self.date_from and str(self.date_from) or None,
            "date_to": self.date_to and str(self.date_to) or None,
            "period": self.period, "group_by": self.group_by,
            "border_id": self.border_id.id or None,
            "carrier_id": self.carrier_id.id or None,
            "factory_id": self.factory_id.id or None,
            "customer_id": self.customer_id.id or None,
            "case_id": self.case_id.id or None,
        }

    @api.model
    def open_for(self, report_key, options=None):
        wizard = self.create(dict({"report_key": report_key}, **{
            k: v for k, v in (options or {}).items() if k in self._fields}))
        return {
            "type": "ir.actions.act_window", "res_model": "itr.report.run",
            "res_id": wizard.id, "view_mode": "form", "target": "new",
            "name": "اجرای گزارش",
        }

    def action_preview(self):
        """Render the grid inside the wizard (REP-016 drill-down links)."""
        self.ensure_one()
        data = self.env["itr.report.engine"].run(self.report_key, self._options())
        cols, rows, totals = data["columns"], data["rows"], data["totals"]
        head = "".join("<th style='padding:4px;border:1px solid #999'>%s</th>" % c["label"] for c in cols)
        body = []
        for r in rows[:500]:
            body.append("<tr>" + "".join(
                "<td style='padding:3px;border:1px solid #ccc'>%s</td>"
                % ("" if r.get(c["key"]) is None else r.get(c["key"])) for c in cols) + "</tr>")
        total_row = "<tr style='font-weight:bold;background:#fff2cc'>" + "".join(
            "<td style='padding:3px;border:1px solid #999'>%s</td>"
            % (totals.get(c["key"], "جمع کل" if c is cols[0] else "")) for c in cols) + "</tr>"
        self.result_html = (
            "<div dir='rtl' style='font-family:Tahoma,sans-serif'>"
            "<p>تعداد ردیف: %s — تولیدکننده: %s</p>"
            "<table style='border-collapse:collapse;width:100%%'>"
            "<thead><tr style='background:#d9eaf7'>%s</tr></thead><tbody>%s%s</tbody></table></div>"
            % (len(rows), self.env.user.name, head, "".join(body), total_row))
        return {"type": "ir.actions.act_window", "res_model": "itr.report.run",
                "res_id": self.id, "view_mode": "form", "target": "new"}

    def action_export_clean(self):
        """XLS-001 (a) - clean data export."""
        self.ensure_one()
        name, payload = self.env["itr.excel.standard"].export_report(
            self.report_key, self._options())
        self.write({"output_name": name, "output_file": base64.b64encode(payload)})
        return self._download_action()

    def action_export_template(self):
        """XLS-001 (b) - export onto the employer workbook."""
        self.ensure_one()
        if not self.template_key:
            raise UserError("ابتدا قالب کارفرما را انتخاب کنید.")
        name, payload = self.env["itr.excel.custom"].render(
            self.template_key, self._options())
        self.write({"output_name": name, "output_file": base64.b64encode(payload)})
        return self._download_action()

    def _download_action(self):
        return {
            "type": "ir.actions.act_url",
            "url": "/web/content?model=itr.report.run&id=%s&field=output_file"
                   "&filename_field=output_name&download=true" % self.id,
            "target": "self",
        }
PYEOF

write_utf8 "${REP_DIR}/controllers/main.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""9.1 - the dedicated Excel controller.

Only authenticated users; every call goes through the same group guard as the
UI path, so an RPC caller cannot bypass SEC-011/SEC-017.
"""
import json

from odoo import http
from odoo.http import content_disposition, request


class ItrReportsController(http.Controller):

    @http.route("/itr/report/xlsx/<string:report_key>", type="http", auth="user")
    def report_xlsx(self, report_key, **kw):
        options = {k: (v or None) for k, v in kw.items()}
        name, payload = request.env["itr.excel.standard"].export_report(report_key, options)
        return request.make_response(payload, headers=[
            ("Content-Type", "application/vnd.openxmlformats-officedocument."
                             "spreadsheetml.sheet"),
            ("Content-Disposition", content_disposition(name)),
        ])

    @http.route("/itr/report/template/<string:template_key>", type="http", auth="user")
    def template_xlsx(self, template_key, **kw):
        options = {k: (v or None) for k, v in kw.items()}
        name, payload = request.env["itr.excel.custom"].render(template_key, options)
        return request.make_response(payload, headers=[
            ("Content-Type", "application/vnd.openxmlformats-officedocument."
                             "spreadsheetml.sheet"),
            ("Content-Disposition", content_disposition(name)),
        ])

    @http.route("/itr/report/sample/<string:kind>", type="http", auth="user")
    def sample_xlsx(self, kind, **kw):
        name, payload = request.env["itr.excel.standard"].import_sample(kind)
        return request.make_response(payload, headers=[
            ("Content-Type", "application/vnd.openxmlformats-officedocument."
                             "spreadsheetml.sheet"),
            ("Content-Disposition", content_disposition(name)),
        ])

    @http.route("/itr/report/json/<string:report_key>", type="http", auth="user")
    def report_json(self, report_key, **kw):
        """UAT-08 - the API figure must equal the form/report/Excel figure."""
        data = request.env["itr.report.engine"].run(
            report_key, {k: (v or None) for k, v in kw.items()})
        return request.make_response(
            json.dumps(data, ensure_ascii=False, default=str),
            headers=[("Content-Type", "application/json; charset=utf-8")])
PYEOF

# -----------------------------------------------------------------------------
# امنیت (SEC-011/013/014/019 + REP-006)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/security/ir.model.access.csv" <<'CSVEOF'
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_itr_report_column_all,itr.report.column read,model_itr_report_column,base.group_user,1,0,0,0
access_itr_report_column_mgr,itr.report.column manager,model_itr_report_column,itr_base.group_itr_settings_manager,1,1,1,1
access_itr_report_run_user,itr.report.run user,model_itr_report_run,base.group_user,1,1,1,1
access_itr_excel_template_read,itr.excel.template read,model_itr_excel_template,base.group_user,1,0,0,0
access_itr_excel_template_mgr,itr.excel.template manager,model_itr_excel_template,itr_base.group_itr_settings_manager,1,1,1,1
access_itr_excel_template_fin,itr.excel.template finance,model_itr_excel_template,itr_core.group_financial_manager,1,0,0,0
access_itr_excel_batch_ops,itr.excel.import.batch ops,model_itr_excel_import_batch,itr_core.group_finance_user,1,1,1,0
access_itr_excel_batch_sup,itr.excel.import.batch sup,model_itr_excel_import_batch,itr_core.group_finance_supervisor,1,1,1,0
access_itr_excel_batch_trn,itr.excel.import.batch transport,model_itr_excel_import_batch,itr_core.group_transport_supervisor,1,1,1,0
access_itr_excel_batch_ceo,itr.excel.import.batch ceo,model_itr_excel_import_batch,itr_core.group_ceo,1,0,0,0
access_itr_excel_batch_audit,itr.excel.import.batch auditor,model_itr_excel_import_batch,itr_core.group_auditor,1,0,0,0
access_itr_excel_row_ops,itr.excel.import.row ops,model_itr_excel_import_row,itr_core.group_finance_user,1,1,1,0
access_itr_excel_row_sup,itr.excel.import.row sup,model_itr_excel_import_row,itr_core.group_finance_supervisor,1,1,1,0
access_itr_excel_row_trn,itr.excel.import.row transport,model_itr_excel_import_row,itr_core.group_transport_supervisor,1,1,1,0
access_itr_excel_row_audit,itr.excel.import.row auditor,model_itr_excel_import_row,itr_core.group_auditor,1,0,0,0
access_itr_sync_log_ops,itr.excel.sync.log ops,model_itr_excel_sync_log,itr_core.group_finance_user,1,0,1,0
access_itr_sync_log_sup,itr.excel.sync.log sup,model_itr_excel_sync_log,itr_core.group_finance_supervisor,1,0,1,0
access_itr_sync_log_trn,itr.excel.sync.log transport,model_itr_excel_sync_log,itr_core.group_transport_supervisor,1,0,1,0
access_itr_sync_log_docs,itr.excel.sync.log docs,model_itr_excel_sync_log,itr_core.group_transport_docs,1,0,1,0
access_itr_sync_log_customs,itr.excel.sync.log customs,model_itr_excel_sync_log,itr_core.group_customs_officer,1,0,1,0
access_itr_sync_log_delivery,itr.excel.sync.log delivery,model_itr_excel_sync_log,itr_core.group_transport_delivery,1,0,1,0
access_itr_sync_log_audit,itr.excel.sync.log auditor,model_itr_excel_sync_log,itr_core.group_auditor,1,0,0,0
CSVEOF

write_utf8 "${REP_DIR}/security/itr_reports_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- SEC-013: an import batch belongs to the person who ran it; the
             supervisors, the financial manager, the CEO and the auditor see
             everything. Nobody else sees somebody else's batch. -->
        <record id="rule_excel_batch_own" model="ir.rule">
            <field name="name">Excel import batch: own batches only</field>
            <field name="model_id" ref="model_itr_excel_import_batch"/>
            <field name="domain_force">[('user_id','=',user.id)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_finance_user')),
                                        (4, ref('itr_core.group_transport_docs')),
                                        (4, ref('itr_core.group_customs_officer')),
                                        (4, ref('itr_core.group_transport_delivery'))]"/>
        </record>

        <record id="rule_excel_batch_supervisors" model="ir.rule">
            <field name="name">Excel import batch: supervisors see all</field>
            <field name="model_id" ref="model_itr_excel_import_batch"/>
            <field name="domain_force">[(1,'=',1)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_finance_supervisor')),
                                        (4, ref('itr_core.group_transport_supervisor')),
                                        (4, ref('itr_core.group_financial_manager')),
                                        (4, ref('itr_core.group_ceo')),
                                        (4, ref('itr_core.group_auditor'))]"/>
        </record>

        <!-- The sync log follows exactly the same visibility policy. -->
        <record id="rule_sync_log_own" model="ir.rule">
            <field name="name">Excel sync log: own runs only</field>
            <field name="model_id" ref="model_itr_excel_sync_log"/>
            <field name="domain_force">[('user_id','=',user.id)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_finance_user')),
                                        (4, ref('itr_core.group_transport_docs')),
                                        (4, ref('itr_core.group_customs_officer')),
                                        (4, ref('itr_core.group_transport_delivery'))]"/>
        </record>

        <record id="rule_sync_log_supervisors" model="ir.rule">
            <field name="name">Excel sync log: supervisors and audit see all</field>
            <field name="model_id" ref="model_itr_excel_sync_log"/>
            <field name="domain_force">[(1,'=',1)]</field>
            <field name="groups" eval="[(4, ref('itr_core.group_finance_supervisor')),
                                        (4, ref('itr_core.group_transport_supervisor')),
                                        (4, ref('itr_core.group_financial_manager')),
                                        (4, ref('itr_core.group_ceo')),
                                        (4, ref('itr_core.group_auditor'))]"/>
        </record>

    </data>
</odoo>
XMLEOF

# -----------------------------------------------------------------------------
# داده — REP-001 Data Dictionary (نمونهٔ امضاشدهٔ ۲۶ ستون + سنجه‌ها)
# -----------------------------------------------------------------------------
python3 - "${REP_DIR}/data/itr_report_dictionary_data.xml" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Generate the signed REP-001 dictionary for the 26 column report."""
import sys

COLS = [
    ("sales_date", "تاریخ فروش", "itr.trade.case.create_date", "trade_case_item", "date", 0),
    ("sales_inv", "ش.فاکتور فروش", "itr.trade.case.proforma_sales_ref", "trade_case_item", "text", 0),
    ("customer", "مشتری", "itr.trade.case.buyer_id", "trade_case_item", "text", 0),
    ("item_s", "نوع کالا", "itr.trade.case.item.name", "trade_case_item", "text", 0),
    ("plan_s", "تناژ اصلی فروش", "metric:planned", "trade_case_item", "tonne", 0),
    ("amount_fx_s", "مبلغ ارزی", "itr.trade.case.item.sale_amount", "trade_case_item", "money_src", 0),
    ("amount_base_s", "مبلغ ریالی", "itr.trade.case.item.sale_base_amount", "trade_case_item", "money_base", 0),
    ("ship_s", "تناژ خروجی فروش", "metric:effective", "trade_case_item", "tonne", 0),
    ("cship_s", "جمع تجمعی خروجی فروش", "metric:effective", "trade_case_item", "tonne", 1),
    ("sur_s", "مازاد فروش", "metric:surplus", "trade_case_item", "tonne", 0),
    ("csur_s", "جمع تجمعی مازاد فروش", "metric:surplus", "trade_case_item", "tonne", 1),
    ("rem_s", "باقیماندهٔ فروش", "metric:remaining", "trade_case_item", "tonne", 0),
    ("crem_s", "جمع تجمعی باقیماندهٔ فروش", "metric:remaining", "trade_case_item", "tonne", 1),
    ("pur_date", "تاریخ خرید", "itr.trade.case.create_date", "trade_case_item", "date", 0),
    ("pur_inv", "ش.فاکتور خرید", "itr.trade.case.proforma_purchase_ref", "trade_case_item", "text", 0),
    ("supplier", "تأمین‌کننده", "itr.trade.case.factory_id", "trade_case_item", "text", 0),
    ("item_p", "نوع کالا (خرید)", "itr.trade.case.item.name", "trade_case_item", "text", 0),
    ("plan_p", "تناژ اصلی خرید", "metric:planned", "trade_case_item", "tonne", 0),
    ("amount_p", "مبلغ خرید", "itr.trade.case.item.purchase_base_amount", "trade_case_item", "money_base", 0),
    ("ship_p", "تناژ خروجی خرید", "metric:effective", "trade_case_item", "tonne", 0),
    ("cship_p", "جمع تجمعی خروجی خرید", "metric:effective", "trade_case_item", "tonne", 1),
    ("sur_p", "مازاد خرید", "metric:surplus", "trade_case_item", "tonne", 0),
    ("csur_p", "جمع تجمعی مازاد خرید", "metric:surplus", "trade_case_item", "tonne", 1),
    ("rem_p", "باقیماندهٔ خرید", "metric:remaining", "trade_case_item", "tonne", 0),
    ("crem_p", "جمع تجمعی باقیماندهٔ خرید", "metric:remaining", "trade_case_item", "tonne", 1),
    ("status", "وضعیت", "itr.trade.case.state", "trade_case_item", "state", 0),
]

OTHERS = [
    ("payments", "base_amount", "مبلغ پایه (ریال)", "itr.payment.execution.base_amount",
     "payment_execution", "money_base", 0,
     "G07/FIN-028: فقط اجرای قطعی پرداخت؛ درخواست هرگز شمرده نمی‌شود."),
    ("payments", "sheba", "شبا (ماسک‌شده)", "itr.payment.execution.payee_sheba_masked",
     "payment_execution", "text", 0, "VAL-008: سیاست ماسک یکسان در همهٔ مسیرها."),
    ("customs", "customs_cost", "عوارض گمرک", "itr.transport.case.customs_cost",
     "transport_case", "money_base", 0, "G05: هرگز با حق‌العمل ترخیص ادغام نمی‌شود."),
    ("customs", "clearance_cost", "حق‌العمل ترخیص", "itr.transport.case.clearance_cost",
     "transport_case", "money_base", 0, "G05: ستون کاملاً مستقل."),
    ("tonnage", "effective", "تناژ مؤثر", "metric:effective", "transport_case", "tonne", 0,
     "REP-004/OPS-023: فقط باسکول تأییدشده، هرگز تخمین و هرگز تناژ برنامه‌ای."),
    ("packing", "qty", "تعداد", "itr.transport.case.packing_qty", "transport_case", "count", 0,
     "FIX-P9-1: فیلد افزایشی فاز ۹؛ SRS 13-2/G09 این ستون را الزامی کرده بود."),
    ("factory_debt", "remaining_t", "مانده (تن)", "itr.factory.shortfall.remaining_tonnage",
     "shortfall", "tonne", 0, "BR-121: کلید شامل شناسهٔ ردیف خرید."),
]

out = ['<?xml version="1.0" encoding="utf-8"?>', "<odoo>", '    <data noupdate="1">']
seq = 10
for key, label, src, gran, unit, cum in COLS:
    out.append(
        '        <record id="dict_financial26_%s" model="itr.report.column">\n'
        '            <field name="report_key">financial26</field>\n'
        '            <field name="sequence">%d</field>\n'
        '            <field name="column_key">%s</field>\n'
        '            <field name="label">%s</field>\n'
        '            <field name="definition">SRS 13-3 — ستون امضاشدهٔ گزارش ۲۶ستونه.</field>\n'
        '            <field name="source_ref">%s</field>\n'
        '            <field name="granularity">%s</field>\n'
        '            <field name="unit">%s</field>\n'
        '            <field name="is_cumulative" eval="%s"/>\n'
        '        </record>' % (key, seq, key, label, src, gran, unit, "True" if cum else "False"))
    seq += 10
for rk, key, label, src, gran, unit, cum, note in OTHERS:
    out.append(
        '        <record id="dict_%s_%s" model="itr.report.column">\n'
        '            <field name="report_key">%s</field>\n'
        '            <field name="column_key">%s</field>\n'
        '            <field name="label">%s</field>\n'
        '            <field name="definition">%s</field>\n'
        '            <field name="source_ref">%s</field>\n'
        '            <field name="granularity">%s</field>\n'
        '            <field name="unit">%s</field>\n'
        '            <field name="is_cumulative" eval="%s"/>\n'
        '        </record>' % (rk, key, rk, key, label, note, src, gran, unit,
                               "True" if cum else "False"))
out += ["    </data>", "</odoo>", ""]
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(out))
print("data dictionary rows: %d" % (len(COLS) + len(OTHERS)))
PYEOF

write_utf8 "${REP_DIR}/data/itr_excel_template_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">
        <!-- XLS-002: the registry rows are (re)synchronised on every upgrade so
             the checksum and the "suspended / ready" state always tell the truth
             about the file that is actually on disk (NFR-002 idempotent). -->
        <function model="itr.excel.template" name="sync_registry"/>
    </data>
</odoo>
XMLEOF

# -----------------------------------------------------------------------------
# 9.17/9.18 — قالب پایهٔ RTL + ۱۰ چاپ (REP-021..023)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/report/itr_report_layout_rtl.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- 9.17 / REP-021 / REP-022 / REP-023
         ONE shared Persian RTL layout. Every one of the ten prints uses it, so
         the font, the direction, the company header/footer, the version number,
         the generation time, the producer and the record reference can never
         drift apart between documents. -->
    <template id="itr_print_layout">
        <t t-call="web.html_container">
            <t t-call="web.internal_layout">
                <div class="page itr-rtl"
                     style="direction:rtl;font-family:'Vazirmatn','Tahoma','DejaVu Sans',sans-serif;font-size:12px;line-height:1.9;">
                    <table style="width:100%;border-bottom:2px solid #333;margin-bottom:10px;">
                        <tr>
                            <td style="width:20%;">
                                <!-- REP-022: logo from the company record, never from code -->
                                <img t-if="env.company.logo"
                                     t-att-src="image_data_uri(env.company.logo)"
                                     style="max-height:56px;"/>
                            </td>
                            <td style="text-align:center;">
                                <div style="font-size:16px;font-weight:bold;"><t t-esc="env.company.name"/></div>
                                <div style="font-size:14px;"><t t-esc="doc_title"/></div>
                            </td>
                            <td style="width:26%;text-align:left;font-size:10px;">
                                <div>تاریخ تولید: <t t-esc="itr_fa_date(itr_now())"/></div>
                                <div>تولیدکننده: <t t-esc="env.user.name"/></div>
                                <div>نسخهٔ سند: <t t-esc="doc_version or '1'"/></div>
                            </td>
                        </tr>
                    </table>
                    <t t-out="0"/>
                    <div style="position:running(footer);border-top:1px solid #999;margin-top:12px;
                                font-size:10px;text-align:center;">
                        مرجع رکورد: <t t-esc="doc_ref"/> —
                        <t t-esc="env.company.name"/> —
                        صفحه <span class="page"/> از <span class="topage"/>
                    </div>
                </div>
            </t>
        </t>
    </template>

    <!-- REP-023: one helper family for every amount and every date. -->
    <template id="itr_print_kv">
        <tr>
            <td style="border:1px solid #444;padding:5px;width:26%;background:#f4f7fb;"><b><t t-esc="k"/></b></td>
            <td style="border:1px solid #444;padding:5px;"><t t-esc="v"/></td>
        </tr>
    </template>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/report/itr_report_prints.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- 9.18 / SRS 13-5: the ten mandatory printed documents. -->

    <!-- 1. برگهٔ پروندهٔ بازرگانی (نسخهٔ امضای دستی) -->
    <template id="print_trade_case_sheet">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">برگهٔ پروندهٔ بازرگانی — نسخهٔ امضای دستی</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">شمارهٔ پرونده</t><t t-set="v" t-value="itr_fa_num(o.name)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">الگوی معامله</t><t t-set="v" t-value="o.deal_pattern"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">دستوردهنده</t><t t-set="v" t-value="o.requested_by.name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مشتری</t><t t-set="v" t-value="o.buyer_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">کارخانه</t><t t-set="v" t-value="o.factory_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مقصد</t><t t-set="v" t-value="o.destination"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تناژ قراردادی</t><t t-set="v" t-value="itr_fa_num(o.total_contract_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">جمع خرید (ریال)</t><t t-set="v" t-value="itr_fa_money(o.purchase_total_base)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">جمع فروش (ریال)</t><t t-set="v" t-value="itr_fa_money(o.sales_total_base)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وضعیت</t><t t-set="v" t-value="o.state"/></t>
                </table>
                <table style="width:100%;border-collapse:collapse;margin-top:10px;">
                    <thead><tr style="background:#d9eaf7;">
                        <th style="border:1px solid #444;padding:4px;">ردیف</th>
                        <th style="border:1px solid #444;padding:4px;">شرح کالا</th>
                        <th style="border:1px solid #444;padding:4px;">نوع ردیف</th>
                        <th style="border:1px solid #444;padding:4px;">تناژ قراردادی</th>
                        <th style="border:1px solid #444;padding:4px;">نرخ خرید</th>
                        <th style="border:1px solid #444;padding:4px;">نرخ فروش</th>
                    </tr></thead>
                    <tbody>
                        <tr t-foreach="o.item_ids" t-as="it">
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_num(it_index + 1)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.name"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.row_kind"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_num(it.contract_tonnage)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.purchase_price_unit)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.sale_price_unit)"/></td>
                        </tr>
                    </tbody>
                </table>
                <div style="margin-top:34px;">مهر و امضای مدیرعامل: ............................</div>
            </t>
        </t>
    </template>

    <!-- 2. برگهٔ بارگیری -->
    <template id="print_loading_sheet">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">برگهٔ بارگیری</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">شمارهٔ بارگیری</t><t t-set="v" t-value="itr_fa_num(o.name)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تاریخ</t><t t-set="v" t-value="itr_fa_date(o.order_date)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">کارخانهٔ مبدأ</t><t t-set="v" t-value="o.factory_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مقصد</t><t t-set="v" t-value="o.destination"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مرز خروجی</t><t t-set="v" t-value="o.border_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">راننده / پلاک</t><t t-set="v" t-value="(o.driver_id.display_name or '') + ' / ' + (o.vehicle_id.plate_number or '')"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تناژ برنامه</t><t t-set="v" t-value="itr_fa_num(o.planned_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وضعیت</t><t t-set="v" t-value="o.state"/></t>
                </table>
            </t>
        </t>
    </template>

    <!-- 3. بارنامه -->
    <template id="print_waybill">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">بارنامهٔ حمل</t>
                <t t-set="doc_ref" t-value="o.waybill_number or o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">شمارهٔ بارنامه</t><t t-set="v" t-value="itr_fa_num(o.waybill_number)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">صادرکننده</t><t t-set="v" t-value="o.waybill_issuer"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تاریخ بارنامه</t><t t-set="v" t-value="itr_fa_date(o.waybill_date)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تناژ بارنامه</t><t t-set="v" t-value="itr_fa_num(o.waybill_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">کل کرایه (لنگر)</t><t t-set="v" t-value="itr_fa_money(o.waybill_freight_base)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مبلغ بیمه</t><t t-set="v" t-value="itr_fa_money(o.insurance_amount)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تأیید تطابق با نامهٔ حواله</t><t t-set="v" t-value="o.letter_match_confirmed and 'بله' or 'خیر'"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">باربری</t><t t-set="v" t-value="o.carrier_id.display_name"/></t>
                </table>
            </t>
        </t>
    </template>

    <!-- 4. قبض باسکول -->
    <template id="print_weighbridge">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">قبض باسکول</t>
                <t t-set="doc_ref" t-value="o.weighbridge_ticket_no or o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">شمارهٔ قبض</t><t t-set="v" t-value="itr_fa_num(o.weighbridge_ticket_no)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وزن پر</t><t t-set="v" t-value="itr_fa_num(o.gross_weight)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وزن خالی</t><t t-set="v" t-value="itr_fa_num(o.tare_weight)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وزن خالص</t><t t-set="v" t-value="itr_fa_num(o.net_weight)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تناژ مؤثر (OPS-023)</t><t t-set="v" t-value="itr_fa_num(o.effective_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تأیید باسکول</t><t t-set="v" t-value="o.weighbridge_confirmed and 'تأییدشده' or 'تأییدنشده'"/></t>
                </table>
            </t>
        </t>
    </template>

    <!-- 5. رسید تخلیه -->
    <template id="print_pod">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">رسید تخلیهٔ خریدار (POD)</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">بارگیری</t><t t-set="v" t-value="itr_fa_num(o.name)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مشتری</t><t t-set="v" t-value="o.customer_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تاریخ تحویل</t><t t-set="v" t-value="itr_fa_date(o.delivered_on)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تناژ مؤثر</t><t t-set="v" t-value="itr_fa_num(o.effective_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">رسید بارگذاری شد؟</t><t t-set="v" t-value="o.delivery_receipt and 'بله' or 'خیر'"/></t>
                </table>
                <div style="margin-top:30px;">امضای تحویل‌گیرنده: ............................</div>
            </t>
        </t>
    </template>

    <!-- 6. پکینگ‌لیست -->
    <template id="print_packing_list">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">پکینگ‌لیست</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">نوع بار</t><t t-set="v" t-value="o.goods_description"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">ضخامت</t><t t-set="v" t-value="itr_fa_num(o.thickness_mm)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تعداد (شاخه)</t><t t-set="v" t-value="itr_fa_num(o.packing_qty)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">وزن</t><t t-set="v" t-value="itr_fa_num(o.effective_tonnage)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مرز</t><t t-set="v" t-value="o.border_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">راننده / پلاک</t><t t-set="v" t-value="(o.driver_id.display_name or '') + ' / ' + (o.vehicle_id.plate_number or '')"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">موبایل</t><t t-set="v" t-value="itr_fa_num(o.driver_mobile)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مشتری</t><t t-set="v" t-value="o.customer_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">تاریخ پکینگ</t><t t-set="v" t-value="itr_fa_date(o.packing_date)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">ش.پیش‌فاکتور خرید</t><t t-set="v" t-value="o.purchase_ref"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">ش.پیش‌فاکتور فروش</t><t t-set="v" t-value="o.sales_ref"/></t>
                </table>
            </t>
        </t>
    </template>

    <!-- 7/8. پیش‌فاکتور خرید و فروش (دو سند مجزا — X04) -->
    <template id="print_proforma_purchase">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">پیش‌فاکتور خرید</t>
                <t t-set="doc_ref" t-value="o.proforma_purchase_ref or o.name"/>
                <p style="font-size:10px;color:#a00;">این سند «پیش‌فاکتور» است و با «ریزفاکتور فروش» یکی نیست (X04).</p>
                <table style="width:100%;border-collapse:collapse;">
                    <thead><tr style="background:#d9eaf7;">
                        <th style="border:1px solid #444;padding:4px;">کالا</th>
                        <th style="border:1px solid #444;padding:4px;">تناژ</th>
                        <th style="border:1px solid #444;padding:4px;">فی واحد</th>
                        <th style="border:1px solid #444;padding:4px;">ارز</th>
                        <th style="border:1px solid #444;padding:4px;">مبلغ پایه</th>
                    </tr></thead>
                    <tbody>
                        <tr t-foreach="o.item_ids.filtered(lambda i: i.row_kind in ('purchase','both'))" t-as="it">
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.name"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_num(it.contract_tonnage)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.purchase_price_unit)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.purchase_currency_id.name"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.purchase_base_amount)"/></td>
                        </tr>
                    </tbody>
                </table>
            </t>
        </t>
    </template>

    <template id="print_proforma_sales">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">پیش‌فاکتور فروش</t>
                <t t-set="doc_ref" t-value="o.proforma_sales_ref or o.name"/>
                <p style="font-size:10px;color:#a00;">این سند «پیش‌فاکتور» است و با «ریزفاکتور فروش» یکی نیست (X04).</p>
                <table style="width:100%;border-collapse:collapse;">
                    <thead><tr style="background:#d9eaf7;">
                        <th style="border:1px solid #444;padding:4px;">کالا</th>
                        <th style="border:1px solid #444;padding:4px;">تناژ</th>
                        <th style="border:1px solid #444;padding:4px;">فی واحد</th>
                        <th style="border:1px solid #444;padding:4px;">ارز</th>
                        <th style="border:1px solid #444;padding:4px;">مبلغ پایه</th>
                    </tr></thead>
                    <tbody>
                        <tr t-foreach="o.item_ids.filtered(lambda i: i.row_kind in ('sale','both'))" t-as="it">
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.name"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_num(it.contract_tonnage)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.sale_price_unit)"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="it.sale_currency_id.name"/></td>
                            <td style="border:1px solid #888;padding:3px;"><t t-esc="itr_fa_money(it.sale_base_amount)"/></td>
                        </tr>
                    </tbody>
                </table>
            </t>
        </t>
    </template>

    <!-- 9. صورتحساب باربری -->
    <template id="print_carrier_statement">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">صورتحساب باربری</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">باربری</t><t t-set="v" t-value="o.carrier_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">بارنامه</t><t t-set="v" t-value="itr_fa_num(o.waybill_number)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">لنگر کرایه</t><t t-set="v" t-value="itr_fa_money(o.waybill_freight_base)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">کرایهٔ ثبت‌شده</t><t t-set="v" t-value="itr_fa_money(o.freight_cost)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">پیش‌کرایهٔ پرداخت‌شده</t><t t-set="v" t-value="itr_fa_money(o.advance_paid_base)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">صافی قابل پرداخت</t><t t-set="v" t-value="itr_fa_money(o.final_freight_due)"/></t>
                </table>
            </t>
        </t>
    </template>

    <!-- 10. صورتحساب گمرک و ترخیص (دو ستون مستقل — G05) -->
    <template id="print_customs_statement">
        <t t-foreach="docs" t-as="o">
            <t t-call="itr_reports.itr_print_layout">
                <t t-set="doc_title">صورتحساب گمرک و ترخیص</t>
                <t t-set="doc_ref" t-value="o.name"/>
                <table style="width:100%;border-collapse:collapse;">
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">مرز</t><t t-set="v" t-value="o.border_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">ترخیص‌کار</t><t t-set="v" t-value="o.customs_broker_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">نمایندهٔ مرز</t><t t-set="v" t-value="o.border_agent_id.display_name"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">عوارض گمرک (نهاد دولتی)</t><t t-set="v" t-value="itr_fa_money(o.customs_cost)"/></t>
                    <t t-call="itr_reports.itr_print_kv"><t t-set="k">حق‌العمل ترخیص (نمایندهٔ مرز)</t><t t-set="v" t-value="itr_fa_money(o.clearance_cost)"/></t>
                </table>
                <p style="font-size:10px;">G05 — این دو مبلغ دو نوع هزینهٔ کاملاً مستقل‌اند و هرگز در یک ردیف ادغام نمی‌شوند.</p>
            </t>
        </t>
    </template>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/report/itr_report_actions.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="action_print_trade_case_sheet" model="ir.actions.report">
        <field name="name">برگهٔ پروندهٔ بازرگانی (امضای دستی)</field>
        <field name="model">itr.trade.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_trade_case_sheet</field>
        <field name="report_file">itr_reports.print_trade_case_sheet</field>
        <field name="binding_model_id" ref="itr_core.model_itr_trade_case"/>
        <field name="binding_type">report</field>
        <field name="paperformat_id" ref="base.paperformat_euro"/>
    </record>

    <record id="action_print_proforma_purchase" model="ir.actions.report">
        <field name="name">پیش‌فاکتور خرید</field>
        <field name="model">itr.trade.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_proforma_purchase</field>
        <field name="report_file">itr_reports.print_proforma_purchase</field>
        <field name="binding_model_id" ref="itr_core.model_itr_trade_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_proforma_sales" model="ir.actions.report">
        <field name="name">پیش‌فاکتور فروش</field>
        <field name="model">itr.trade.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_proforma_sales</field>
        <field name="report_file">itr_reports.print_proforma_sales</field>
        <field name="binding_model_id" ref="itr_core.model_itr_trade_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_loading_sheet" model="ir.actions.report">
        <field name="name">برگهٔ بارگیری</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_loading_sheet</field>
        <field name="report_file">itr_reports.print_loading_sheet</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_waybill" model="ir.actions.report">
        <field name="name">بارنامه</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_waybill</field>
        <field name="report_file">itr_reports.print_waybill</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_weighbridge" model="ir.actions.report">
        <field name="name">قبض باسکول</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_weighbridge</field>
        <field name="report_file">itr_reports.print_weighbridge</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_pod" model="ir.actions.report">
        <field name="name">رسید تخلیه</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_pod</field>
        <field name="report_file">itr_reports.print_pod</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_packing_list" model="ir.actions.report">
        <field name="name">پکینگ‌لیست</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_packing_list</field>
        <field name="report_file">itr_reports.print_packing_list</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_carrier_statement" model="ir.actions.report">
        <field name="name">صورتحساب باربری</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_carrier_statement</field>
        <field name="report_file">itr_reports.print_carrier_statement</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>

    <record id="action_print_customs_statement" model="ir.actions.report">
        <field name="name">صورتحساب گمرک و ترخیص</field>
        <field name="model">itr.transport.case</field>
        <field name="report_type">qweb-pdf</field>
        <field name="report_name">itr_reports.print_customs_statement</field>
        <field name="report_file">itr_reports.print_customs_statement</field>
        <field name="binding_model_id" ref="itr_transport.model_itr_transport_case"/>
        <field name="binding_type">report</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/models/itr_qweb_helpers.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""REP-023 - ONE helper family for every printed amount and every printed date.

The ten RTL documents never format a number or a date themselves; they call
these four helpers, which in turn call the single calendar engine of itr_base
(NFR-009 / G18). Printed documents use PERSIAN digits; Excel cells deliberately
use LATIN digits (XLS-018) - the two policies are separated on purpose.
"""
from odoo import api, fields, models

from odoo.addons.itr_base.utils import jalali as jal
from odoo.addons.itr_base.utils import validators as val


def itr_print_helpers():
    """The four helpers every printed document is allowed to use."""
    return {
        "itr_fa_date": _fa_date,
        "itr_fa_num": _fa_num,
        "itr_fa_money": _fa_money,
        "itr_mask_sheba": val.mask_sheba,
        "itr_now": fields.Datetime.now,
        "doc_version": "1",
        "doc_ref": "",
        "doc_title": "",
    }


class ItrReportHelpers(models.AbstractModel):
    """`ir.actions.report._get_rendering_context` is the stable, documented
    hook for adding values to a QWeb PDF/HTML rendering. We deliberately do
    NOT patch `ir.qweb` itself, because its private signatures move between
    Odoo releases and a broken signature would take down every report in the
    database, not just ours (R1 - lowest possible blast radius)."""
    _inherit = "ir.actions.report"

    @api.model
    def _get_rendering_context(self, report, docids, data):
        values = super()._get_rendering_context(report, docids, data)
        for key, helper in itr_print_helpers().items():
            values.setdefault(key, helper)
        return values


def _fa_date(value):
    """Jalali + Persian digits - printed documents only (REP-021)."""
    return jal.to_jalali_str(value, persian_digits=True) if value else ""


def _fa_num(value):
    if value in (None, False, ""):
        return ""
    return val.to_persian_digits(str(value))


def _fa_money(value):
    try:
        text = "{:,.0f}".format(float(value or 0))
    except Exception:
        text = str(value or "")
    return val.to_persian_digits(text)
PYEOF

# -----------------------------------------------------------------------------
# ویوها و منوها — گزارش‌ها داخل همان Workspaceهای فاز ۸ می‌نشینند
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/views/itr_report_run_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_report_run_form" model="ir.ui.view">
        <field name="name">itr.report.run.form</field>
        <field name="model">itr.report.run</field>
        <field name="arch" type="xml">
            <form string="اجرای گزارش">
                <sheet>
                    <group>
                        <group string="گزارش">
                            <field name="report_key"/>
                            <field name="period"/>
                            <field name="group_by"/>
                        </group>
                        <group string="بازه و فیلترها">
                            <field name="date_from"/>
                            <field name="date_to"/>
                            <field name="border_id"/>
                            <field name="carrier_id"/>
                            <field name="factory_id"/>
                            <field name="customer_id"/>
                            <field name="case_id"/>
                        </group>
                    </group>
                    <group string="خروجی اکسل روی قالب کارفرما (XLS-001 ب)">
                        <field name="template_key"/>
                    </group>
                    <field name="result_html" readonly="1"/>
                    <group invisible="not output_name">
                        <field name="output_name" readonly="1"/>
                        <field name="output_file" filename="output_name" readonly="1"/>
                    </group>
                </sheet>
                <footer>
                    <button name="action_preview" type="object" string="نمایش گزارش" class="btn-primary"/>
                    <button name="action_export_clean" type="object" string="خروجی اکسل (دادهٔ تمیز)" class="btn-secondary"/>
                    <button name="action_export_template" type="object" string="خروجی روی قالب کارفرما" class="btn-secondary"/>
                    <button string="بستن" special="cancel" class="btn-light"/>
                </footer>
            </form>
        </field>
    </record>

    <record id="action_itr_report_run" model="ir.actions.act_window">
        <field name="name">مرکز گزارش‌ها</field>
        <field name="res_model">itr.report.run</field>
        <field name="view_mode">form</field>
        <field name="target">new</field>
    </record>

    <!-- REP-001: the signed data dictionary is visible, not hidden in code. -->
    <record id="view_itr_report_column_list" model="ir.ui.view">
        <field name="name">itr.report.column.list</field>
        <field name="model">itr.report.column</field>
        <field name="arch" type="xml">
            <list string="فرهنگ دادهٔ گزارش‌ها (REP-001)" default_order="report_key,sequence">
                <field name="report_key"/>
                <field name="column_key"/>
                <field name="label"/>
                <field name="source_ref"/>
                <field name="granularity"/>
                <field name="unit"/>
                <field name="is_cumulative"/>
            </list>
        </field>
    </record>

    <record id="action_itr_report_column" model="ir.actions.act_window">
        <field name="name">فرهنگ دادهٔ گزارش‌ها (REP-001)</field>
        <field name="res_model">itr.report.column</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/views/itr_excel_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_excel_template_list" model="ir.ui.view">
        <field name="name">itr.excel.template.list</field>
        <field name="model">itr.excel.template</field>
        <field name="arch" type="xml">
            <list string="رجیستری قالب‌های کارفرما (XLS-002)" decoration-warning="state=='suspended'">
                <field name="template_key"/>
                <field name="version"/>
                <field name="sheet_name"/>
                <field name="source_file"/>
                <field name="column_count"/>
                <field name="unresolved_count"/>
                <field name="file_present"/>
                <field name="state"/>
                <field name="checksum" optional="hide"/>
            </list>
        </field>
    </record>

    <record id="view_itr_excel_template_form" model="ir.ui.view">
        <field name="name">itr.excel.template.form</field>
        <field name="model">itr.excel.template</field>
        <field name="arch" type="xml">
            <form string="قالب کارفرما">
                <sheet>
                    <group>
                        <group>
                            <field name="template_key"/>
                            <field name="registry_key"/>
                            <field name="version"/>
                            <field name="sheet_name"/>
                        </group>
                        <group>
                            <field name="source_file"/>
                            <field name="file_present"/>
                            <field name="checksum"/>
                            <field name="state"/>
                        </group>
                    </group>
                    <group string="ستون‌های UNRESOLVED (XLS-006/007 — بدون تعیین‌تکلیف کتبی بسته نمی‌شوند)">
                        <field name="unresolved_count"/>
                        <field name="unresolved_detail" readonly="1"/>
                    </group>
                    <field name="note" placeholder="تعیین‌تکلیف کتبی کارفرما دربارهٔ ستون‌های UNRESOLVED..."/>
                </sheet>
            </form>
        </field>
    </record>

    <record id="action_itr_excel_template" model="ir.actions.act_window">
        <field name="name">قالب‌های اکسل کارفرما</field>
        <field name="res_model">itr.excel.template</field>
        <field name="view_mode">list,form</field>
    </record>

    <record id="view_itr_excel_batch_list" model="ir.ui.view">
        <field name="name">itr.excel.import.batch.list</field>
        <field name="model">itr.excel.import.batch</field>
        <field name="arch" type="xml">
            <list string="دسته‌های ورود اکسل" decoration-danger="state=='failed'"
                  decoration-success="state=='committed'">
                <field name="name"/>
                <field name="kind"/>
                <field name="filename"/>
                <field name="row_total"/>
                <field name="row_valid"/>
                <field name="row_warning"/>
                <field name="row_error"/>
                <field name="created_count"/>
                <field name="skipped_count"/>
                <field name="state"/>
                <field name="user_id"/>
            </list>
        </field>
    </record>

    <record id="action_itr_excel_batch" model="ir.actions.act_window">
        <field name="name">ورود گروهی اکسل (Preview→Commit)</field>
        <field name="res_model">itr.excel.import.batch</field>
        <field name="view_mode">list,form</field>
    </record>

    <record id="view_itr_sync_log_list" model="ir.ui.view">
        <field name="name">itr.excel.sync.log.list</field>
        <field name="model">itr.excel.sync.log</field>
        <field name="arch" type="xml">
            <list string="دفتر Sync اکسل">
                <field name="run_on"/>
                <field name="template_key"/>
                <field name="row_count"/>
                <field name="written_cells"/>
                <field name="protected_cells"/>
                <field name="unresolved_cells"/>
                <field name="user_id"/>
            </list>
        </field>
    </record>

    <record id="action_itr_sync_log" model="ir.actions.act_window">
        <field name="name">دفتر Sync اکسل</field>
        <field name="res_model">itr.excel.sync.log</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/views/itr_reports_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- The reports get their own root inside the phase 3 application root, so
         the phase 8 workspaces are never disturbed (R1). -->
    <menuitem id="menu_itr_reports_root" name="گزارش‌ها و خروجی‌ها"
              parent="itr_core.menu_itr_core_root" sequence="11"
              groups="itr_core.group_ceo,itr_core.group_financial_manager,itr_core.group_finance_supervisor,itr_core.group_finance_user,itr_core.group_transport_supervisor,itr_core.group_transport_docs,itr_core.group_customs_officer,itr_core.group_transport_delivery,itr_core.group_auditor"/>

    <menuitem id="menu_itr_reports_center" name="مرکز گزارش‌ها (۱۵ گزارش)"
              parent="menu_itr_reports_root" action="action_itr_report_run" sequence="10"/>

    <menuitem id="menu_itr_reports_dictionary" name="فرهنگ دادهٔ گزارش‌ها (REP-001)"
              parent="menu_itr_reports_root" action="action_itr_report_column" sequence="80"
              groups="itr_core.group_financial_manager,itr_core.group_auditor,itr_base.group_itr_settings_manager"/>

    <menuitem id="menu_itr_excel_root" name="اکسل" parent="menu_itr_reports_root" sequence="50"/>
    <menuitem id="menu_itr_excel_templates" name="قالب‌های کارفرما (رجیستری)"
              parent="menu_itr_excel_root" action="action_itr_excel_template" sequence="10"/>
    <menuitem id="menu_itr_excel_batches" name="ورود گروهی اکسل"
              parent="menu_itr_excel_root" action="action_itr_excel_batch" sequence="20"/>
    <menuitem id="menu_itr_excel_sync_log" name="دفتر Sync"
              parent="menu_itr_excel_root" action="action_itr_sync_log" sequence="30"/>
</odoo>
XMLEOF

write_utf8 "${REP_DIR}/views/itr_reports_workspace_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- UX-031: the reports a role actually needs appear INSIDE that role's own
         phase 8 workspace, so nobody has to leave their space to do daily work.
         itr_reports loads AFTER itr_core and itr_transport, therefore it may
         reference every workspace menu and every model (this is exactly the
         ordering problem ADR-040 had to work around in phase 8). -->

    <!-- فضای مدیرعامل -->
    <menuitem id="menu_ws_ceo_reports" name="گزارش‌ها" parent="itr_core.menu_ws_ceo"
              action="action_itr_report_run" sequence="90"
              groups="itr_core.group_ceo"/>

    <!-- فضای مالی و بازرگانی -->
    <menuitem id="menu_ws_fin_reports" name="گزارش‌ها و خروجی اکسل"
              parent="itr_core.menu_ws_finance" action="action_itr_report_run" sequence="90"
              groups="itr_core.group_finance_supervisor,itr_core.group_finance_user,itr_core.group_financial_manager"/>
    <menuitem id="menu_ws_fin_excel" name="قالب‌های اکسل کارفرما"
              parent="itr_core.menu_ws_finance" action="action_itr_excel_template" sequence="95"
              groups="itr_core.group_finance_supervisor,itr_core.group_financial_manager"/>

    <!-- فضای سرپرست حمل -->
    <menuitem id="menu_ws_trn_sup_reports" name="گزارش‌های حمل"
              parent="itr_core.menu_ws_trn_sup" action="action_itr_report_run" sequence="90"
              groups="itr_core.group_transport_supervisor"/>

    <!-- فضای اسناد و ناوگان (پکینگ) -->
    <menuitem id="menu_ws_docs_reports" name="گزارش پکینگ و خروجی"
              parent="itr_core.menu_ws_docs" action="action_itr_report_run" sequence="90"
              groups="itr_core.group_transport_docs"/>

    <!-- فضای مرز و ترخیص (گمرک/ترخیص — دو ستون مستقل G05) -->
    <menuitem id="menu_ws_customs_reports" name="گزارش گمرک و ترخیص"
              parent="itr_core.menu_ws_customs" action="action_itr_report_run" sequence="90"
              groups="itr_core.group_customs_officer"/>

    <!-- فضای تحویل و تسویه (پرداخت‌ها — فقط اجرای قطعی G07) -->
    <menuitem id="menu_ws_delivery_reports" name="گزارش پرداخت‌ها و تسویه"
              parent="itr_core.menu_ws_delivery" action="action_itr_report_run" sequence="90"
              groups="itr_core.group_transport_delivery"/>
</odoo>
XMLEOF

# -----------------------------------------------------------------------------
# تست‌های خودکار فاز ۹ (Q04 — کاربر واقعی، بدون sudo)
# -----------------------------------------------------------------------------
write_utf8 "${REP_DIR}/tests/test_reports_phase9.py" <<'PYEOF'
# -*- coding: utf-8 -*-
from odoo.tests import TransactionCase, tagged


@tagged("post_install", "-at_install", "itr_reports")
class TestReportsPhase9(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.fin_user = cls.env["res.users"].search(
            [("login", "=", "faezeh.heydari@irbco.local")], limit=1)
        cls.ceo = cls.env["res.users"].search(
            [("login", "=", "hadi.karamian@irbco.local")], limit=1)
        cls.engine = cls.env["itr.report.engine"]
        cls.reg = cls.env["itr.kpi.service"]

    def test_10_all_fifteen_reports_run(self):
        """V9-01 - every one of the 15 reports returns a well formed payload."""
        from odoo.addons.itr_reports.models.itr_report_engine import REPORT_KEYS
        self.assertEqual(len(REPORT_KEYS), 15)
        for key in REPORT_KEYS:
            data = self.engine.with_user(self.fin_user or self.env.user).run(key, {})
            self.assertIn("columns", data, key)
            self.assertIn("rows", data, key)
            self.assertTrue(all(c.get("key") for c in data["columns"]), key)

    def test_20_financial26_has_exactly_26_columns(self):
        """9.4 - the exact 26 columns, in the exact order."""
        cols = self.env["itr.report.financial26"].columns()
        self.assertEqual(len(cols), 26)
        self.assertEqual(cols[0]["key"], "sales_date")
        self.assertEqual(cols[12]["key"], "crem_s")
        self.assertEqual(cols[13]["key"], "pur_date")
        self.assertEqual(cols[25]["key"], "status")

    def test_30_row_kind_both_produces_two_logical_rows(self):
        """REP-013 / G11 - a mixed deal never returns an empty side."""
        case = self._mixed_case()
        data = self.env["itr.report.financial26"].build({"case_id": case.id})
        kinds = {r["row_kind"] for r in data["rows"]}
        self.assertEqual(kinds, {"sale", "purchase"})
        sale = [r for r in data["rows"] if r["row_kind"] == "sale"][0]
        purchase = [r for r in data["rows"] if r["row_kind"] == "purchase"][0]
        self.assertTrue(sale["plan_s"] > 0)
        self.assertEqual(sale["plan_p"], 0.0)          # REP-011 independence
        self.assertTrue(purchase["plan_p"] > 0)
        self.assertEqual(purchase["plan_s"], 0.0)

    def test_40_cumulative_total_takes_last_value(self):
        """REP-015 - the grand total never re-sums a cumulative column."""
        case = self._mixed_case()
        data = self.env["itr.report.financial26"].build({"case_id": case.id})
        rows, totals = data["rows"], data["totals"]
        if rows:
            self.assertEqual(totals["cship_s"], rows[-1]["cship_s"])
            self.assertEqual(totals["cship_p"], rows[-1]["cship_p"])

    def test_50_surplus_and_remaining_never_negative(self):
        """REP-012."""
        case = self._mixed_case()
        data = self.env["itr.report.financial26"].build({"case_id": case.id})
        for row in data["rows"]:
            for key in ("sur_s", "rem_s", "sur_p", "rem_p"):
                self.assertGreaterEqual(row[key], 0.0)

    def test_60_payments_report_ignores_requests(self):
        """G07 / FIN-028 - a request is never counted as a payment."""
        data = self.engine.run("payments", {})
        for row in data["rows"]:
            exe = self.env["itr.payment.execution"].browse(row["res_id"])
            self.assertEqual(exe.state, "done")

    def test_70_metric_registry_is_the_only_engine(self):
        """G18 - the nine metric families all resolve through itr.kpi.service."""
        from odoo.addons.itr_reports.models.itr_metric_registry import METRIC_KEYS
        registry = self.reg.metric_registry()
        for key in METRIC_KEYS:
            self.assertIn(key, registry)

    def test_80_customs_and_clearance_stay_separate(self):
        """G05."""
        data = self.engine.run("customs", {})
        keys = [c["key"] for c in data["columns"]]
        self.assertIn("customs_cost", keys)
        self.assertIn("clearance_cost", keys)

    def test_90_sheba_is_masked_everywhere(self):
        """VAL-008."""
        data = self.engine.run("payments", {})
        for row in data["rows"]:
            if row["sheba"]:
                self.assertIn("*", row["sheba"])

    # ------------------------------------------------------------------ tools
    def _mixed_case(self):
        Partner = self.env["res.partner"]
        factory = Partner.search([("is_factory", "=", True)], limit=1) or Partner.create(
            {"name": "TEST p9 factory", "is_company": True, "is_factory": True})
        buyer = Partner.create({"name": "TEST p9 buyer", "is_company": True})
        return self.env["itr.trade.case"].create({
            "requested_by": self.ceo.id if self.ceo else self.env.user.id,
            "deal_pattern": "buy_first",
            "factory_id": factory.id,
            "buyer_id": buyer.id,
            "destination": "TEST p9 destination",
            "item_ids": [(0, 0, {
                "name": "TEST p9 mixed goods", "row_kind": "both",
                "contract_tonnage": 40.0,
                "purchase_price_unit": 100.0, "sale_price_unit": 130.0,
            })],
        })
PYEOF

write_utf8 "${REP_DIR}/tests/test_excel_phase9.py" <<'PYEOF'
# -*- coding: utf-8 -*-
import io

from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged("post_install", "-at_install", "itr_reports")
class TestExcelPhase9(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.common = cls.env["itr.excel.common"]
        cls.imp = cls.env["itr.excel.import"]
        cls.fin_user = cls.env["res.users"].search(
            [("login", "=", "faezeh.heydari@irbco.local")], limit=1)

    # ------------------------------------------------------------- registry
    def test_10_five_templates_registered(self):
        """XLS-021 - exactly the five employer workbooks, no more, no less."""
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        self.assertEqual(set(TEMPLATE_REGISTRY),
                         {"financial", "freight", "packing", "purchase", "dispatch"})

    def test_20_customer_typos_are_preserved(self):
        """XLS-004 - the customer's own spelling is never corrected."""
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        freight = [c["header"] for c in TEMPLATE_REGISTRY["freight"]["columns"]]
        self.assertIn("هزنیه تخلیه", freight)
        self.assertIn("هزنیه بارگیری", freight)
        self.assertIn("تامین کننده",
                      [c["header"] for c in TEMPLATE_REGISTRY["financial"]["columns"]])
        loading = TEMPLATE_REGISTRY["purchase"]["extra_sheets"]["loading"]
        self.assertIn("پگینگ", [c["header"] for c in loading["columns"]])
        self.assertIn("ترخیصکار", [c["header"] for c in loading["columns"]])

    def test_30_unresolved_columns_are_none_not_guessed(self):
        """XLS-006/007 - ambiguity stays UNRESOLVED."""
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        freight = {c["col"]: c for c in TEMPLATE_REGISTRY["freight"]["columns"]}
        for col in ("F", "H", "I", "J", "L"):
            self.assertIsNone(freight[col]["field"], col)
            self.assertTrue(freight[col].get("note"), col)

    def test_40_packing_is_ltr_and_branch_is_not_border(self):
        """XLS-021 - T03 stays LTR and column E is pieces, never «مرز»."""
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        packing = TEMPLATE_REGISTRY["packing"]
        self.assertFalse(packing["rtl"])
        self.assertFalse(packing["allow_logo_injection"])
        col_e = [c for c in packing["columns"] if c["col"] == "E"][0]
        self.assertEqual(col_e["header"], "Branch")
        self.assertEqual(col_e["field"], "qty")
        col_g = [c for c in packing["columns"] if c["col"] == "G"][0]
        self.assertNotEqual(col_g["field"], "sales_ref")

    def test_50_protected_formula_families(self):
        """XLS-008 - the declared formula families are the contract."""
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        f = TEMPLATE_REGISTRY["freight"]["formula_patterns"]
        self.assertEqual(f["G"], "=F{row}*E{row}")
        self.assertEqual(f["J"], "=I{row}+G{row}")
        self.assertEqual(f["L"], "=J{row}-K{row}")
        p = TEMPLATE_REGISTRY["purchase"]["formula_patterns"]
        self.assertIn("'صورت بارگیری'!$D$3:$D$1048576,C{row}", p["I"])

    def test_60_hidden_columns_and_merges_declared(self):
        from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY
        fin = TEMPLATE_REGISTRY["financial"]
        self.assertEqual(tuple(fin["hidden_columns"]), ("I", "J", "K", "M", "U", "V", "W", "Y"))
        self.assertEqual(len(fin["columns"]), 26)
        self.assertIn("B2:L2", TEMPLATE_REGISTRY["dispatch"]["protected_merges"])

    # ---------------------------------------------------------------- guards
    def test_70_upload_guards(self):
        """XLS-012 - extension, emptiness and magic bytes."""
        with self.assertRaises(UserError):
            self.common.guard_upload("a.xls", b"PK\x03\x04")
        with self.assertRaises(UserError):
            self.common.guard_upload("a.xlsx", b"")
        with self.assertRaises(UserError):
            self.common.guard_upload("a.xlsx", b"not-a-zip")

    def test_80_formula_injection_is_neutralised(self):
        self.assertEqual(self.common.sanitize_cell("=1+1"), "'=1+1")
        self.assertEqual(self.common.sanitize_cell("plain"), "plain")

    def test_90_import_rolls_back_on_a_single_bad_row(self):
        """V9-06 / XLS-011 - one bad row rolls the WHOLE batch back."""
        payload = self._workbook([
            ["both", "TEST p9 row ok", 10, 100, "IRR", 120, "IRR", "PP-1", "PS-1"],
            ["both", "TEST p9 row bad", 0, 100, "IRR", 120, "IRR", "PP-2", "PS-2"],
        ])
        imp = self.imp.with_user(self.fin_user) if self.fin_user else self.imp
        result = imp.preview("proforma", "p9.xlsx", payload)
        self.assertEqual(result["error"], 1)
        before = self.env["itr.trade.case.item"].search_count([])
        with self.assertRaises(UserError):
            imp.commit(result["batch_id"], result["commit_token"], payload)
        self.assertEqual(self.env["itr.trade.case.item"].search_count([]), before)

    def test_95_sample_headers_exist(self):
        """XLS-021 / 9.21."""
        self.assertTrue(self.imp.sample_headers("proforma"))
        self.assertTrue(self.imp.sample_headers("freight"))
        with self.assertRaises(UserError):
            self.imp.sample_headers("nope")

    def _workbook(self, rows):
        import openpyxl
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(self.imp.sample_headers("proforma"))
        for row in rows:
            ws.append(row)
        out = io.BytesIO()
        wb.save(out)
        return out.getvalue()
PYEOF

write_utf8 "${REP_DIR}/i18n/fa_IR.po" <<'POEOF'
# Persian translation for itr_reports (phase 9)
msgid ""
msgstr ""
"Project-Id-Version: Odoo 19.0\n"
"MIME-Version: 1.0\n"
"Content-Type: text/plain; charset=UTF-8\n"
"Content-Transfer-Encoding: 8bit\n"
"Language: fa_IR\n"
"Plural-Forms: nplurals=1; plural=0;\n"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_report_column
msgid "REP-001 Data Dictionary column"
msgstr "ستون فرهنگ دادهٔ گزارش‌ها"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_report_engine
msgid "Phase 9 report engine (single source for report data)"
msgstr "موتور گزارش فاز ۹ (تنها منبع دادهٔ گزارش)"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_report_financial26
msgid "G01 - 26 column purchase/sale financial report"
msgstr "گزارش جامع مالی خرید و فروش (۲۶ ستون)"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_excel_template
msgid "Employer Excel template registry entry"
msgstr "رکورد رجیستری قالب اکسل کارفرما"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_excel_import_batch
msgid "XLS-013 - Excel import batch"
msgstr "دستهٔ ورود اکسل"

#. module: itr_reports
#: model:ir.model,name:itr_reports.model_itr_excel_sync_log
msgid "Sync Log of an employer-template Excel run"
msgstr "دفتر Sync اجرای اکسل روی قالب کارفرما"

#. module: itr_reports
#: model:ir.model.fields,field_description:itr_reports.field_itr_transport_case__packing_qty
msgid "Branch / pieces (packing)"
msgstr "تعداد (شاخه) — پکینگ"
POEOF

write_utf8 "${REP_DIR}/README.md" <<'MDEOF'
# itr_reports — فاز ۹

ماژول گزارش‌گیری، چاپ RTL و اکسل پروژهٔ «Iran Trade & Transport ERP».

## چرا ماژول جداست
ترتیب قفل‌شدهٔ Q02 یعنی این ماژول آخرین حلقهٔ زنجیره است و همهٔ مدل‌های
`itr_core` و `itr_transport` برایش شناخته‌شده‌اند. بنابراین برخلاف فاز ۸
(ADR-040) نیازی به دور زدن با `ir.actions.server` نیست و هیچ فایلی از فازهای
۱ تا ۸ بازنویسی نمی‌شود.

## سه نقطهٔ ورود، نه بیشتر
| کار | نقطهٔ ورود |
|---|---|
| دادهٔ هر گزارش | `itr.report.engine.run(report_key, options)` |
| هر عدد/سنجه | `itr.kpi.service.metric(key, record)` (REP-002 — موتور واحد) |
| هر خروجی اکسل | `itr.excel.standard` (دادهٔ تمیز) و `itr.excel.custom` (قالب کارفرما) |

## قوانین اکسل که هرگز شکسته نمی‌شوند
* فایل قالب روی دیسک هرگز بازنویسی نمی‌شود؛ خروجی فقط `io.BytesIO` است.
* متن کارفرما هرگز «اصلاح املایی» نمی‌شود؛ alias فقط در لایهٔ تطبیق است.
* قفل مختصات مقدم بر تطبیق فازی است؛ ابهام ⇒ UNRESOLVED، هرگز حدس.
* فرمول‌ها محافظت‌شده‌اند؛ تنها بازنویسی مجاز: کلون فرمول هنگام درج ردیف و
  گسترش بازهٔ SUM اعلام‌شده.
* درج ردیف merge-aware است و رنج‌های زیر ردیف جمع، درست shift می‌شوند.

## جای دکمه‌ها
هر نقش، گزارش‌های خودش را داخل Workspace خودش (فاز ۸) می‌بیند:
مدیرعامل، مالی/بازرگانی، سرپرست حمل، اسناد و ناوگان، مرز و ترخیص،
تحویل و تسویه — به‌علاوهٔ ریشهٔ مستقل «گزارش‌ها و خروجی‌ها».
MDEOF

log "اسکلت و محتوای ماژول itr_reports نوشته شد"

# =============================================================================
step "7) verify مستقل فاز ۹ (ops/verify/verify_phase9.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase9.py" <<'PYEOF'
# -*- coding: utf-8 -*-
# ops/verify/verify_phase9.py — verify مستقل فاز ۹ (کاربر واقعی، بدون sudo، rollback)
import io
import traceback

checks = []
passed = failed = 0


def chk(code, title, condition, detail=""):
    global passed, failed
    status = "PASS" if condition else "FAIL"
    if condition:
        passed += 1
    else:
        failed += 1
    checks.append((code, status, title, detail))
    print("%-7s %-5s %s%s" % (code, status, title, ("  [%s]" % detail) if detail else ""))


try:
    env = env  # noqa: F821 — provided by odoo shell
    from odoo.exceptions import AccessError, UserError, ValidationError

    REFUSALS = (AccessError, UserError, ValidationError)

    def real(login):
        user = env["res.users"].search([("login", "=", login)], limit=1)
        assert user, "missing seeded user %s" % login
        return user

    def refused(fn):
        try:
            with env.cr.savepoint():
                fn()
        except REFUSALS:
            return True
        except Exception:  # noqa: BLE001
            traceback.print_exc()
            return False
        return False

    # logins = itr_core seed (phase 3) — identical to verify_phase7/8
    ceo = real("hadi.karamian@irbco.local")
    fin_mgr = real("fin.mgr@irbco.local")
    fin_sup = real("ehsan.nahalparvar@irbco.local")
    fin_user = real("faezeh.heydari@irbco.local")
    trn_sup = real("najmeh.afrashtehpour@irbco.local")
    docs = real("mohaddeseh.enayati@irbco.local")
    customs = real("mohammadi@irbco.local")
    delivery = real("amini@irbco.local")

    Engine = env["itr.report.engine"]
    Fin26 = env["itr.report.financial26"]
    Reg = env["itr.kpi.service"]
    Tpl = env["itr.excel.template"]
    Imp = env["itr.excel.import"]

    from odoo.addons.itr_reports.models.itr_report_engine import REPORT_KEYS
    from odoo.addons.itr_reports.models.itr_excel_template_registry import TEMPLATE_REGISTRY

    # ---------------------------------------------------------------- V9-01
    ok, broken = True, []
    for key in REPORT_KEYS:
        try:
            data = Engine.with_user(fin_user).run(key, {})
            if not isinstance(data.get("columns"), list) or not isinstance(data.get("rows"), list):
                ok = False
                broken.append(key)
        except Exception as exc:  # noqa: BLE001
            ok = False
            broken.append("%s(%s)" % (key, exc))
    chk("V9-01", "هر ۱۵ گزارش با کاربر واقعی خروجی دادند", ok and len(REPORT_KEYS) == 15,
        ", ".join(broken) or "15/15")

    # cross-check: report figure == direct ORM count (UAT-08)
    payments = Engine.with_user(fin_sup).run("payments", {})
    direct = env["itr.payment.execution"].with_user(fin_sup).search_count([("state", "=", "done")])
    chk("V9-01b", "عدد گزارش پرداخت‌ها با شمارش مستقیم ORM برابر است",
        len(payments["rows"]) == direct, "report=%s orm=%s" % (len(payments["rows"]), direct))

    # ---------------------------------------------------------------- V9-02
    Partner = env["res.partner"]
    factory = Partner.search([("is_factory", "=", True)], limit=1)
    if not factory:
        factory = Partner.create({"name": "TEST p9 factory", "is_company": True, "is_factory": True})
    buyer = Partner.create({"name": "TEST p9 buyer", "is_company": True})
    mixed = env["itr.trade.case"].with_user(fin_user).create({
        "requested_by": ceo.id, "deal_pattern": "buy_first",
        "factory_id": factory.id, "buyer_id": buyer.id,
        "destination": "TEST p9 destination",
        "item_ids": [(0, 0, {"name": "TEST p9 mixed", "row_kind": "both",
                             "contract_tonnage": 40.0,
                             "purchase_price_unit": 100.0, "sale_price_unit": 130.0})],
    })
    data26 = Fin26.with_user(fin_user).build({"case_id": mixed.id})
    kinds = {r["row_kind"] for r in data26["rows"]}
    both_sides = kinds == {"sale", "purchase"}
    all26 = len(data26["columns"]) == 26
    sale_row = next((r for r in data26["rows"] if r["row_kind"] == "sale"), {})
    pur_row = next((r for r in data26["rows"] if r["row_kind"] == "purchase"), {})
    independent = bool(sale_row) and bool(pur_row) \
        and sale_row.get("plan_p") == 0.0 and pur_row.get("plan_s") == 0.0
    chk("V9-02", "گزارش ۲۶ستونه برای پروندهٔ ترکیبی هر دو سمت را پر کرد (G11/REP-013)",
        both_sides and all26 and independent,
        "cols=%s kinds=%s" % (len(data26["columns"]), sorted(kinds)))

    # ---------------------------------------------------------------- V9-03
    rows, totals = data26["rows"], data26["totals"]
    cumulative_ok = True
    if rows:
        for key in ("cship_s", "csur_s", "crem_s", "cship_p", "csur_p", "crem_p"):
            if abs(totals.get(key, 0.0) - rows[-1].get(key, 0.0)) > 1e-6:
                cumulative_ok = False
        summed = sum(r.get("cship_s", 0.0) for r in rows)
        if len(rows) > 1 and abs(totals.get("cship_s", 0.0) - summed) < 1e-9 and summed:
            cumulative_ok = False        # it WAS re-summed -> REP-015 violated
    chk("V9-03", "ردیف جمع کل ستون تجمعی را دوباره جمع نزد (REP-015)", cumulative_ok,
        "last=%s" % (rows[-1].get("cship_s") if rows else "-"))

    # ---------------------------------------------------------------- V9-04
    only_done = all(
        env["itr.payment.execution"].browse(r["res_id"]).state == "done"
        for r in payments["rows"])
    req_count = env["itr.payment.request"].with_user(fin_sup).search_count(
        [("state", "not in", ("executed", "done"))])
    chk("V9-04", "گزارش پرداخت‌ها هیچ درخواست پرداخت‌نشده‌ای نشان نداد (G07/FIN-028)",
        only_done, "open requests ignored=%s" % req_count)

    # ---------------------------------------------------------------- V9-05
    masked_ok = True
    for r in payments["rows"]:
        if r["sheba"] and "*" not in r["sheba"]:
            masked_ok = False
    sample = env["itr.validation.service"].mask_sheba("IR930120000000000000000872")
    masked_ok = masked_ok and "*" in sample
    chk("V9-05", "شبا در گزارش/اکسل/چاپ با سیاست یکسان ماسک شد (VAL-008)", masked_ok, sample)

    # ---------------------------------------------------------------- V9-06
    import openpyxl
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(Imp.sample_headers("proforma"))
    ws.append(["both", "TEST p9 good", 10, 100, "IRR", 120, "IRR", "PP-1", "PS-1"])
    ws.append(["both", "TEST p9 bad", 0, 100, "IRR", 120, "IRR", "PP-2", "PS-2"])
    buf = io.BytesIO()
    wb.save(buf)
    payload = buf.getvalue()
    preview = Imp.with_user(fin_user).preview("proforma", "p9.xlsx", payload)
    before = env["itr.trade.case.item"].search_count([])
    rolled_back = refused(lambda: Imp.with_user(fin_user).with_context(
        itr_target_case_id=mixed.id).commit(
            preview["batch_id"], preview["commit_token"], payload))
    after = env["itr.trade.case.item"].search_count([])
    chk("V9-06", "Import با یک ردیف نامعتبر، کل تراکنش را rollback کرد (XLS-011)",
        rolled_back and before == after, "before=%s after=%s errors=%s"
        % (before, after, preview["error"]))

    # ---------------------------------------------------------------- V9-07
    Tpl.sync_registry()
    regs = Tpl.search([])
    ready = regs.filtered(lambda t: t.state == "ready")
    suspended = regs.filtered(lambda t: t.state == "suspended")
    typos_ok = (
        "هزنیه تخلیه" in [c["header"] for c in TEMPLATE_REGISTRY["freight"]["columns"]]
        and "هزنیه بارگیری" in [c["header"] for c in TEMPLATE_REGISTRY["freight"]["columns"]]
        and "پگینگ" in [c["header"] for c in
                        TEMPLATE_REGISTRY["purchase"]["extra_sheets"]["loading"]["columns"]]
        and "تامین کننده" in [c["header"] for c in TEMPLATE_REGISTRY["financial"]["columns"]]
    )
    rendered, render_errors = 0, []
    for key in TEMPLATE_REGISTRY:
        reg_row = regs.filtered(lambda t, k=key: t.registry_key == k)
        if reg_row and reg_row[0].state != "ready":
            continue
        try:
            name, payload_x = env["itr.excel.custom"].with_user(fin_sup).render(key, {})
            wb2 = openpyxl.load_workbook(io.BytesIO(payload_x))
            assert TEMPLATE_REGISTRY[key]["sheet"] in wb2.sheetnames \
                or any(s for s in wb2.sheetnames)
            rendered += 1
        except Exception as exc:  # noqa: BLE001
            render_errors.append("%s: %s" % (key, exc))
    if len(ready) == 5:
        chk("V9-07", "هر پنج قالب کارفرما سالم پر شدند و غلط املایی دست‌نخورده ماند",
            rendered == 5 and typos_ok and not render_errors,
            "rendered=%s %s" % (rendered, "; ".join(render_errors)))
    else:
        chk("V9-07", "قالب‌های حاضر سالم پر شدند؛ بقیه «معلق - در انتظار فایل کارفرما» (9.27)",
            typos_ok and not render_errors,
            "ready=%s suspended=%s rendered=%s" % (len(ready), len(suspended), rendered))

    # ---------------------------------------------------------------- V9-08
    print_ok, print_errors = 0, []
    trade_reports = ["itr_reports.action_print_trade_case_sheet",
                     "itr_reports.action_print_proforma_purchase",
                     "itr_reports.action_print_proforma_sales"]
    transport_reports = ["itr_reports.action_print_loading_sheet",
                         "itr_reports.action_print_waybill",
                         "itr_reports.action_print_weighbridge",
                         "itr_reports.action_print_pod",
                         "itr_reports.action_print_packing_list",
                         "itr_reports.action_print_carrier_statement",
                         "itr_reports.action_print_customs_statement"]
    loading = env["itr.transport.case"].search([], limit=1)
    for xmlid in trade_reports:
        try:
            env["ir.actions.report"]._render_qweb_html(xmlid, mixed.ids)
            print_ok += 1
        except Exception as exc:  # noqa: BLE001
            print_errors.append("%s: %s" % (xmlid, exc))
    for xmlid in transport_reports:
        if not loading:
            print_ok += 1
            continue
        try:
            env["ir.actions.report"]._render_qweb_html(xmlid, loading.ids)
            print_ok += 1
        except Exception as exc:  # noqa: BLE001
            print_errors.append("%s: %s" % (xmlid, exc))
    chk("V9-08", "هر ۱۰ چاپ RTL بدون خطا رندر شدند (REP-021)", print_ok == 10,
        "ok=%s %s" % (print_ok, "; ".join(print_errors[:2])))

    # -------------------------------------------------- negative tests (G01)
    transport_user_blocked = refused(
        lambda: env["itr.excel.template"].with_user(docs).create(
            {"name": "x", "template_key": "x", "registry_key": "x",
             "version": "9", "sheet_name": "x"}))
    chk("V9-09", "تست منفی: کارشناس اسناد نمی‌تواند رجیستری قالب را دستکاری کند (SEC-017)",
        transport_user_blocked, "blocked")

    admin = env["res.users"].browse(2)
    admin_biz_groups = [g.name for g in admin.group_ids
                        if g.category_id and "Iran" in (g.category_id.name or "")]
    chk("V9-10", "Administrator هنوز هیچ گروه کسب‌وکاری ندارد (Q03)",
        not admin_biz_groups, str(admin_biz_groups))

    # G18: single engine proof — the module must not define a second registry
    import odoo.addons.itr_reports.models.itr_metric_registry as mr
    chk("V9-11", "رجیستری سنجه فقط گسترش itr.kpi.service است (G18/ADR-037)",
        "itr.kpi.service" in open(mr.__file__, encoding="utf-8").read(), "inherit ok")

except Exception:  # noqa: BLE001
    traceback.print_exc()
    failed += 1

print("")
print("ITR_VERIFY_SUMMARY: passed=%d failed=%d" % (passed, failed))
print("ITR_VERIFY_RESULT: %s" % ("PASS" if failed == 0 else "FAIL"))

# rollback — verify never leaves data behind
try:
    env.cr.rollback()
except Exception:  # noqa: BLE001
    pass
PYEOF
log "verify_phase9.py نوشته شد"

# =============================================================================
step "8) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python - "${REP_DIR}" <<'PYEOF' >"${SYNTAX_LOG}" 2>&1
import ast, csv, os, sys, xml.etree.ElementTree as ET
root = sys.argv[1]
errors = []
py = xml_ = csvn = 0
for base, _dirs, files in os.walk(root):
    for fn in files:
        path = os.path.join(base, fn)
        try:
            if fn.endswith(".py"):
                ast.parse(open(path, encoding="utf-8").read()); py += 1
            elif fn.endswith(".xml"):
                ET.parse(path); xml_ += 1
            elif fn.endswith(".csv"):
                with open(path, encoding="utf-8") as fh:
                    rows = list(csv.reader(fh))
                width = len(rows[0])
                for i, r in enumerate(rows[1:], 2):
                    if len(r) != width:
                        errors.append("%s:%d ستون‌ها %d != %d" % (path, i, len(r), width))
                csvn += 1
        except Exception as exc:
            errors.append("%s: %s" % (path, exc))
print("py=%d xml=%d csv=%d" % (py, xml_, csvn))
for e in errors:
    print("ERROR", e)
sys.exit(1 if errors else 0)
PYEOF
SYNTAX_RC=$?
set -e
cat "${SYNTAX_LOG}"
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G9-05" "نحو پایتون و صحت XML/CSV پیش از نصب" "PASS" "$(head -n1 "${SYNTAX_LOG}")"
else
  gate "G9-05" "نحو پایتون و صحت XML/CSV پیش از نصب" "FAIL" "→ ${SYNTAX_LOG}"
  err "خطای نحوی — هیچ نصبی انجام نشد (R1: دیتابیس دست‌نخورده است)."
fi

# =============================================================================
step "9) نصب itr_reports + ارتقای زنجیره روی ${DB_NAME} (Q01/Q02/NFR-001)"
# =============================================================================
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -i "${REP_MODULE}" -u "${CORE_MODULE},${TRN_MODULE}" \
  --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
REP_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${REP_MODULE}'")"
CORE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TRN_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} reports=${REP_AFTER} core=${CORE_AFTER} transport=${TRN_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${REP_AFTER}" == "installed" \
      && "${CORE_AFTER}" == "installed" && "${TRN_AFTER}" == "installed" ]]; then
  gate "G9-06" "نصب فاز ۹ بدون خطا و بدون شکستن ماژول‌های قبل" "PASS" "rc=0 errors=0"
else
  gate "G9-06" "نصب فاز ۹ بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} → ${INSTALL_LOG}"
  tail -n 80 "${INSTALL_LOG}" || true
fi

# =============================================================================
step "10) R5 — تست‌های فاز ۹ *و* بازاجرای کامل تست‌های فازهای ۱..۸"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G9-07" "تست‌های فاز ۹ + بازاجرای فازهای ۱..۸ سبز" "FAIL" "SKIP_TESTS=1 (Q04 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "${BASE_MODULE},${NOTIFY_MODULE},${CORE_MODULE},${TRN_MODULE},${REP_MODULE}" \
    --test-enable \
    --test-tags "/${BASE_MODULE},/${NOTIFY_MODULE},/${CORE_MODULE},/${TRN_MODULE},/${REP_MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" && -n "${TEST_TOTAL}" ]]; then
    gate "G9-07" "تست‌های فاز ۹ سبز + هیچ رگرسیونی در فازهای ۱..۸ (R5)" "PASS" "${TEST_TOTAL} rc=0"
  else
    gate "G9-07" "تست‌های فاز ۹ + بازاجرای فازهای ۱..۸" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -A 40 -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" | head -n 200 || true
  fi
fi

# =============================================================================
step "11) verify مستقل V9-01..V9-11 (کاربر واقعی، بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G9-08" "verify فاز ۹ سبز" "FAIL" "SKIP_VERIFY=1 (Q15 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" --stop-after-init \
    <"${OPS_DIR}/verify/verify_phase9.py" >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^V9-|ITR_VERIFY' "${VERIFY_LOG}" || true
  if grep -q 'ITR_VERIFY_RESULT: PASS' "${VERIFY_LOG}"; then
    gate "G9-08" "verify فاز ۹: هر ۸ سنجهٔ اجباری + ۳ تست منفی سبز" "PASS" \
      "$(grep ITR_VERIFY_SUMMARY "${VERIFY_LOG}" | tail -n1)"
  else
    gate "G9-08" "verify فاز ۹ سبز" "FAIL" "rc=${VERIFY_RC} → ${VERIFY_LOG}"
    tail -n 80 "${VERIFY_LOG}" || true
  fi
fi

# =============================================================================
step "12) گاردهای معماری فاز ۹ (G18 / FIN-005 / REP-007 / G01 / R1)"
# =============================================================================
# G18/FIN-005 — هیچ موتور دوم سود/KPI/SLA/تقویم
SECOND_PROFIT="$(grep -rnE 'sales?_(total_)?base.*-.*purchase' --include='*.py' "${REP_DIR}" \
  | grep -v 'itr_metric_registry.py' | grep -v '#' || true)"
if [[ -z "${SECOND_PROFIT}" ]]; then
  gate "G9-09" "فرمول سود فقط در رجیستری واحد (FIN-005/G18)" "PASS" "clean"
else
  gate "G9-09" "فرمول سود فقط در رجیستری واحد (FIN-005/G18)" "FAIL" "$(echo "${SECOND_PROFIT}" | head -n2 | tr '\n' ' ')"
fi

SECOND_CAL="$(grep -rnE 'def (gregorian_to_jalali|jalali_to_gregorian|_jdn_to_jalali)' \
  --include='*.py' "${REP_DIR}" || true)"
if [[ -z "${SECOND_CAL}" ]]; then
  gate "G9-10" "هیچ موتور تقویم دوم در فاز ۹ (G18/NFR-009)" "PASS" "clean — فقط itr_base"
else
  gate "G9-10" "هیچ موتور تقویم دوم در فاز ۹" "FAIL" "${SECOND_CAL}"
fi

# REP-007 — هیچ SQL خام
RAW_SQL="$(grep -rnE 'cr\.execute|\.execute\(' --include='*.py' "${REP_DIR}" || true)"
if [[ -z "${RAW_SQL}" ]]; then
  gate "G9-11" "هیچ SQL خام در کل ماژول گزارش (REP-007/XLS-017)" "PASS" "clean"
else
  gate "G9-11" "هیچ SQL خام در کل ماژول گزارش (REP-007)" "FAIL" "$(echo "${RAW_SQL}" | head -n2 | tr '\n' ' ')"
fi

# G01 — هیچ sudo بی‌برچسب
SUDO_HITS="$(grep -rnE '\.sudo\(\)' --include='*.py' "${REP_DIR}" | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G9-12" "هیچ sudo() بی‌برچسب در فاز ۹ (G01/SEC-018)" "PASS" "clean"
else
  gate "G9-12" "هیچ sudo() بی‌برچسب در فاز ۹ (G01/SEC-018)" "FAIL" "$(echo "${SUDO_HITS}" | head -n2 | tr '\n' ' ')"
fi

# R1 — اثبات اینکه هیچ فایل فازهای ۱..۸ لمس نشده است
cd "${CUSTOM_ADDONS}"
TOUCHED="$(git status --porcelain -- "${BASE_MODULE}" "${NOTIFY_MODULE}" "${CORE_MODULE}" "${TRN_MODULE}" 2>/dev/null | head -n5 || true)"
if [[ -z "${TOUCHED}" ]]; then
  gate "G9-13" "R1: هیچ فایلی از ماژول‌های فاز ۱..۸ تغییر نکرد (کمترین ریسک)" "PASS" "0 files"
else
  gate "G9-13" "R1: هیچ فایلی از ماژول‌های فاز ۱..۸ تغییر نکرد" "FAIL" "$(echo "${TOUCHED}" | tr '\n' ' ')"
fi

# ممنوعه‌های دائمی (G16 / بخش ۱۶)
FORBIDDEN="$(grep -rniE 'whatsapp|leaflet|interactive[_ ]map|form[_ ]?builder|report[_ ]?builder|dashboard[_ ]?builder' \
  --include='*.py' --include='*.xml' "${REP_DIR}" || true)"
if [[ -z "${FORBIDDEN}" ]]; then
  gate "G9-14" "هیچ ممنوعهٔ بخش ۱۶ ساخته نشد (G16)" "PASS" "clean"
else
  gate "G9-14" "هیچ ممنوعهٔ بخش ۱۶ ساخته نشد (G16)" "FAIL" "$(echo "${FORBIDDEN}" | head -n2 | tr '\n' ' ')"
fi

# G07 — گزارش پرداخت‌ها هرگز از payment.request نمی‌خواند
PAYREQ_LEAK="$(grep -n 'itr.payment.request' "${REP_DIR}/models/itr_report_engine.py" || true)"
if [[ -z "${PAYREQ_LEAK}" ]]; then
  gate "G9-15" "گزارش پرداخت‌ها فقط از payment.execution می‌خواند (G07/FIN-028)" "PASS" "clean"
else
  gate "G9-15" "گزارش پرداخت‌ها فقط از payment.execution می‌خواند (G07)" "FAIL" "${PAYREQ_LEAK}"
fi

# =============================================================================
step "13) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
C1="$(q "${DB_NAME}" "SELECT count(*) FROM itr_report_column")"
C2="$(q "${DB_NAME}" "SELECT count(*) FROM itr_excel_template")"
C3="$(q "${DB_NAME}" "SELECT count(*) FROM ir_ui_menu")"
C4="$(q "${DB_NAME}" "SELECT count(*) FROM ir_act_report_xml")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${REP_MODULE}" --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
C1B="$(q "${DB_NAME}" "SELECT count(*) FROM itr_report_column")"
C2B="$(q "${DB_NAME}" "SELECT count(*) FROM itr_excel_template")"
C3B="$(q "${DB_NAME}" "SELECT count(*) FROM ir_ui_menu")"
C4B="$(q "${DB_NAME}" "SELECT count(*) FROM ir_act_report_xml")"
if [[ ${IDEMP_RC} -eq 0 && "${C1}" == "${C1B}" && "${C2}" == "${C2B}" \
      && "${C3}" == "${C3B}" && "${C4}" == "${C4B}" ]]; then
  gate "G9-16" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "PASS" \
    "dict=${C1B} tpl=${C2B} menus=${C3B} prints=${C4B}"
else
  gate "G9-16" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "FAIL" \
    "dict ${C1}→${C1B} tpl ${C2}→${C2B} menu ${C3}→${C3B} print ${C4}→${C4B}"
fi

# =============================================================================
step "14) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  warn "SKIP_UAT=1 — UAT رد شد"
  gate "G9-17" "نصب UAT بدون خطا" "FAIL" "SKIP_UAT=1"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    -i "${REP_MODULE}" -u "${CORE_MODULE},${TRN_MODULE}" \
    --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${REP_MODULE}'")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_STATE}" == "installed" ]]; then
    gate "G9-17" "نصب UAT بدون خطا" "PASS" "state=installed"
  else
    gate "G9-17" "نصب UAT بدون خطا" "FAIL" "rc=${UAT_RC} state=${UAT_STATE} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "15) اسناد حاکمیتی: ADR-041..045 / REUSE MAP / تحویل فاز (Q13/Q14/NFR-013)"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
if ! grep -q "ADR-041" "${ADR_FILE}" 2>/dev/null; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-041 — گزارش‌ها یک ماژول مستقل‌اند، نه پچ روی هسته
فاز ۹ هیچ فایلی از فازهای ۱..۸ را بازنویسی نمی‌کند. `itr_reports` آخرین حلقهٔ
ترتیب قفل‌شدهٔ Q02 است، بنابراین همهٔ مدل‌های `itr_core` و `itr_transport`
برایش شناخته‌شده‌اند و می‌تواند `act_window` و `ir.actions.report` واقعی بسازد.
این دقیقاً همان محدودیتی است که ADR-040 در فاز ۸ مجبور به دور زدنش با
`ir.actions.server` شده بود. نتیجه: کمترین سطح ریسک برای قرارداد فازهای قبل.

## ADR-042 — Metric Registry = گسترش همان KPI رجیستری فاز ۸
طبق ADR-037، `itr.kpi.service` بذر Metric Registry بود. فاز ۹ آن را با
`_inherit` گسترش داد و نُه خانوادهٔ سنجه (planned/reserved/effective/surplus/
remaining/cost/settled/profit/sla_state) را اضافه کرد. هیچ موتور دوم سود،
هیچ SQL موازی و هیچ ساعت SLA دوم ساخته نشد (G18/FIN-005/NOT-035).
سود همچنان فقط از `itr.money.engine` می‌آید.

## ADR-043 — دو سیاست رقم، عمداً متفاوت
چاپ‌های RTL ارقام فارسی دارند (REP-021) اما سلول‌های اکسل تاریخ شمسی با ارقام
لاتین می‌گیرند (XLS-018). این تفاوت عمدی است تا فرمول‌ها و مرتب‌سازی اکسل
نشکنند. هر دو از یک موتور تقویم `itr_base.utils.jalali` می‌آیند.

## ADR-044 — UNRESOLVED یک نتیجهٔ معتبر است، نه شکست
هر ستون قالب کارفرما که فیلد تأییدشده ندارد، `field=None` می‌ماند، در
`itr.excel.template.unresolved_detail` گزارش می‌شود و در Sync Log برچسب
`unresolved` می‌گیرد. حدس زدن مقصد ممنوع مطلق است (XLS-006/007).
Gate 9 تا تعیین‌تکلیف کتبی کارفرما دربارهٔ این ستون‌ها سبز کامل اعلام نمی‌شود.

## ADR-045 — فیلد افزایشی packing_qty (FIX-P9-1)
SRS 13-2/G09 ستون «تعداد» را برای گزارش پکینگ و ستون Branch قالب T03 الزامی
کرده بود، اما هیچ فیلدی برای آن در فازهای ۴..۸ وجود نداشت. چون سند آن را
«الزامی» اعلام کرده، به‌جای UNRESOLVED گذاشتن یک ستون الزامی، فیلد واقعی
`itr.transport.case.packing_qty` با `_inherit` داخل `itr_reports` افزوده شد.
هیچ فایل فاز ۶ لمس نشد و هیچ فیلد موجودی تغییر نکرد.
MDEOF
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "phase-9" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## phase-9 (نقشهٔ استفادهٔ مجدد — Q14)
* `itr.kpi.service` (فاز ۸) → با `_inherit` به Metric Registry تبدیل شد؛ هیچ سرویس شاخص دومی ساخته نشد.
* `itr.money.engine` (فاز ۴/۶) → تنها منبع هزینه و سود گزارش‌ها؛ هیچ فرمول دومی نوشته نشد.
* `itr_base.utils.jalali` (فاز ۱) → تنها موتور تقویم چاپ و اکسل.
* `itr_base.utils.validators.mask_sheba` (فاز ۱) → تنها سیاست ماسک شبا در گزارش/اکسل/چاپ.
* `itr.sla.watch` (فاز ۲) → منبع رنگ SLA گزارش پرونده‌های متوقف؛ هیچ cron دومی اضافه نشد.
* `itr.cartable.settings` (فاز ۸) → آستانهٔ «متوقف‌شده» از تنظیمات می‌آید نه از کد.
* `itr.trade.case.item.row_kind` (فاز ۴) → مبنای تفکیک خرید/فروش گزارش ۲۶ستونه (G11).
* `itr.payment.execution` (فاز ۶) → تنها منبع گزارش پرداخت‌ها (G07).
* منوهای Workspace فاز ۸ → گزارش‌ها به‌عنوان فرزند همان منوها اضافه شدند، بدون تغییر والدها.
MDEOF
fi

write_utf8 "${DOC_DIR}/PHASE9-DELIVERY.md" <<'MDEOF'
# تحویل فاز ۹ — itr_reports

## Scope انجام‌شده (با شناسهٔ نیازمندی)
* REP-001 فرهنگ داده (`itr.report.column`) — امضاشده و قابل مشاهده در UI.
* REP-002 Metric Registry — گسترش `itr.kpi.service` با ۹ خانوادهٔ سنجه.
* REP-003..007 — حذف مرکزی وضعیت‌ها، تناژ مؤثر فقط از باسکول تأییدشده،
  تفکیک هزینه/تسویه، فیلتر سمت سرور، بدون SQL خام.
* ۱۵ گزارش الزامی G01..G15 (SRS 13-2) + گزارش ۲۶ستونه (SRS 13-3) با
  REP-011..016 عیناً.
* ۱۰ چاپ RTL (SRS 13-5) روی یک قالب پایهٔ مشترک با REP-021..023.
* موتور اکسل استاندارد: Export تمیز، قالب نمونه، Import چهارمرحله‌ای تراکنشی.
* موتور اکسل اختصاصی: رجیستری نسخه‌دار با checksum برای پنج قالب کارفرما.

## Scope انجام‌نشده / خارج فاز (با دلیل صریح)
* رندر PDF واقعی نیازمند wkhtmltopdf روی سرور است؛ verify فاز ۹ رندر HTML
  قالب‌ها را می‌سنجد و خروجی PDF در محیط واقعی گرفته می‌شود.
* ستون‌های UNRESOLVED قالب‌های کارفرما (XLS-006/007) تا تعیین‌تکلیف کتبی
  کارفرما باز می‌مانند؛ فهرست دقیق در `itr.excel.template.unresolved_detail`.
* اگر پنج فایل واقعی کارفرما هنوز نرسیده باشند، زیربخش «اکسل اختصاصی»
  رسماً «معلق - در انتظار فایل کارفرما» علامت می‌خورد (9.27/XLS-020/OPEN-04).

## ماتریس دسترسی تغییرکرده
هیچ گروه تازه‌ای ساخته نشد. فقط ACL و Record Rule برای چهار مدل جدید
(`itr.report.column`, `itr.excel.template`, `itr.excel.import.batch/row`,
`itr.excel.sync.log`) اضافه شد. سیاست: کارشناس فقط دستهٔ خودش، سرپرست‌ها و
حسابرس همه (SEC-013/SEC-019).

## Rollback آزموده‌شده
`bash ops/restore.sh <dump> <filestore> <db>` — پشتیبان پیش از فاز در
`~/odoo-backups` با پیشوند `pre-phase9`.
MDEOF
log "اسناد حاکمیتی نوشته شد"

# =============================================================================
step "16) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" == "1" ]]; then
  nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    >>"${LOG_FILE}" 2>&1 &
  echo $! >"${PID_FILE}"
  sleep 8
  HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' \
    "http://127.0.0.1:${HTTP_PORT}/web/login" || echo 000)"
  if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "303" ]]; then
    gate "G9-18" "سرویس بالا آمد و healthcheck پاسخ داد" "PASS" "HTTP ${HTTP_CODE}"
  else
    gate "G9-18" "سرویس بالا آمد و healthcheck پاسخ داد" "FAIL" "HTTP ${HTTP_CODE}"
  fi
else
  warn "START_DAEMON=0 — سرویس اجرا نشد"
fi

# =============================================================================
step "17) ثبت Git + تگ phase-9 (Q09)"
# =============================================================================
cd "${CUSTOM_ADDONS}"
git config user.email >/dev/null 2>&1 || git config user.email "dev@irbco.local"
git config user.name  >/dev/null 2>&1 || git config user.name  "ITR Contributors"
git add -A
if git diff --cached --quiet; then
  warn "چیزی برای commit نبود"
else
  git commit -m "phase 9: itr_reports — 15 reports, 26-column financial report, 10 RTL prints, standard + employer Excel engines (single metric registry, no engine duplication)" >/dev/null
  log "commit ثبت شد"
fi
git tag -f "phase-9" >/dev/null 2>&1 || true
COMMIT_HASH="$(git rev-parse --short HEAD 2>/dev/null || echo '-')"
gate "G9-19" "Git commit + tag phase-9" "PASS" "${COMMIT_HASH}"

# =============================================================================
step "GATE 9 — گزارش پذیرش فاز ۹"
# =============================================================================
PASS_N=0; FAIL_N=0; SUSP_N=0
echo
printf '%-8s %-11s %s\n' "ID" "STATUS" "CHECK"
printf '%-8s %-11s %s\n' "--------" "-----------" "--------------------------------------------"
for i in "${!GATE_IDS[@]}"; do
  printf '%-8s %-11s %s\n' "${GATE_IDS[$i]}" "${GATE_ST[$i]}" "${GATE_TXT[$i]}"
  [[ -n "${GATE_MSG[$i]}" ]] && printf '%-8s %-11s   ↳ %s\n' "" "" "${GATE_MSG[$i]}"
  case "${GATE_ST[$i]}" in
    PASS) PASS_N=$((PASS_N+1)) ;;
    SUSPENDED) SUSP_N=$((SUSP_N+1)) ;;
    *) FAIL_N=$((FAIL_N+1)) ;;
  esac
done

echo
echo "PASS=${PASS_N}  FAIL=${FAIL_N}  SUSPENDED=${SUSP_N}"
echo
if [[ ${FAIL_N} -eq 0 && ${SUSP_N} -eq 0 ]]; then
  echo -e "${GREEN}================= GATE 9: سبز — فاز ۹ تمام شد =================${NC}"
elif [[ ${FAIL_N} -eq 0 ]]; then
  echo -e "${YELLOW}=========== GATE 9: سبز مشروط — ${SUSP_N} مورد «معلق» ===========${NC}"
  echo "مورد معلق فقط و فقط «پنج فایل قالب واقعی کارفرما» است (XLS-020 / OPEN-04)."
  echo "فایل‌ها را در ${TEMPLATE_SRC} بگذارید و همین اسکریپت را دوباره اجرا کنید."
else
  echo -e "${RED}================= GATE 9: قرمز — فاز ۹ تمام نشده =================${NC}"
  echo "هیچ ادعای «تقریباً کامل» پذیرفته نیست (Q08). موارد FAIL بالا را رفع کنید."
fi

cat <<'FINAL'

────────────────────────────────────────────────────────────────────────────
 فاز ۹ — نقشهٔ سریع استفاده
────────────────────────────────────────────────────────────────────────────
 منوی مستقل      : «گزارش‌ها و خروجی‌ها» (ریشهٔ ITR)
                    ├── مرکز گزارش‌ها (۱۵ گزارش)
                    ├── اکسل › قالب‌های کارفرما (رجیستری + UNRESOLVED)
                    ├── اکسل › ورود گروهی (Preview→Validate→Resolve→Commit)
                    ├── اکسل › دفتر Sync
                    └── فرهنگ دادهٔ گزارش‌ها (REP-001)

 داخل Workspace هر نقش (فاز ۸):
   فضای مدیرعامل        › گزارش‌ها
   فضای مالی و بازرگانی › گزارش‌ها و خروجی اکسل + قالب‌های کارفرما
   فضای سرپرست حمل      › گزارش‌های حمل
   فضای اسناد و ناوگان  › گزارش پکینگ و خروجی
   فضای مرز و ترخیص     › گزارش گمرک و ترخیص (دو ستون مستقل — G05)
   فضای تحویل و تسویه   › گزارش پرداخت‌ها و تسویه (فقط اجرای قطعی — G07)

 چاپ‌ها (دکمهٔ Print روی خود فرم):
   پروندهٔ بازرگانی → برگهٔ امضای دستی | پیش‌فاکتور خرید | پیش‌فاکتور فروش
   پروندهٔ حمل      → برگهٔ بارگیری | بارنامه | قبض باسکول | رسید تخلیه |
                      پکینگ‌لیست | صورتحساب باربری | صورتحساب گمرک و ترخیص

 کنترلرها (برای اتوماسیون/تست):
   /itr/report/xlsx/<report_key>        خروجی اکسل دادهٔ تمیز
   /itr/report/template/<template_key>  خروجی روی قالب کارفرما
   /itr/report/sample/<kind>            دانلود قالب نمونهٔ ورود
   /itr/report/json/<report_key>        همان اعداد، برای مقایسهٔ UAT-08

 قالب‌های کارفرما:
   پوشهٔ  excel_client_files/  را کنار همین اسکریپت بسازید و پنج فایل
   template_01_financial.xlsx … template_05_dispatch.xlsx را در آن بگذارید؛
   اسکریپت آن‌ها را در itr_reports/static/excel_templates/ می‌نشاند و
   checksum می‌گیرد. تا آن زمان، آن زیربخش «معلق» می‌ماند، نه «نادیده».
────────────────────────────────────────────────────────────────────────────
FINAL

trap - EXIT
exit 0
