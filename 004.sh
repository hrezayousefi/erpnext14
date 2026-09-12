#!/usr/bin/env bash
# =============================================================================
# script-04-itr-core-trade.sh (004.sh) — PHASE 4 (COMPLETE) — Iran Trade & Transport ERP
# Odoo 19.0 | File-First | Idempotent | Test-First | Gate-Enforced | No sudo-proof
#
# فاز ۴ — پروندهٔ بازرگانی، گردش تأییدات و گارد امضا : itr_core (بخش دوم)
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt  ← «فاز ۴» بندهای 4.1..4.11
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← بخش ۳، ۶، ۷ (نقشهٔ خط‌وفلش)،
#       بخش ۸-۴ (money_engine)، بخش ۱۰-۳ (shortfall)، بخش ۱۲ (پایهٔ کارتابل/ارجاع)
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh، 001.sh، 002.sh و 003.sh همین مخزن.
#
# اصلاح این نسخه نسبت به اجرای قبلی (سه تغییر حداقلی، بدون دور زدن هیچ Gate):
#   [FIX-1] قید یکتای BR-121 روی itr.factory.shortfall با models.Constraint
#           تعریف می‌شود؛ Odoo 19 رسماً `_sql_constraints` را پشتیبانی نمی‌کند
#           (هشدار «Model attribute '_sql_constraints' is no longer supported»
#           در لاگ نصب) و به همین دلیل ایندکس یکتا ساخته نمی‌شد
#           (shortfall_uniq=0 و شکست test_26).
#   [FIX-2] ترتیب import مدل‌ها: itr_trade_case پیش از itr_trade_case_item تا
#           comodel 'itr.trade.case' هنگام setup فیلد case_id در رجیستری باشد.
#   [FIX-3] شمارش شکست تست فقط روی خطوط واقعی unittest است
#           ((FAIL|ERROR): TestClass.test_...)؛ لاگ SQL موردانتظار
#           «duplicate key» در test_26 اثبات صحت قید است نه شکست
#           (در اجرای قبل rc=0 ولی fails=1 شمرده شد). هیچ تستی حذف/غیرفعال نشد.
#
# پوشش کامل چک‌لیست فاز ۴:
#   4.1  مدل itr.trade.case با چهار تب + Sequence خودکار + mail.thread/activity
#   4.2  requested_by: دامنهٔ کلاینتی + Constraint سرور (فقط group_ceo) + قفل پس از ثبت
#   4.3  مدل itr.trade.case.item: ابعاد/ضخامت/تناژ قراردادی/نرخ خرید/نرخ فروش +
#        چهار فیلد استاندارد چندارزی مستقل برای هر سمت (G12) + row_kind (G11)
#   4.4  دو الگوی معامله A/B (BR-003/004)؛ در الگوی B هیچ itr.sales.slip —
#        حتی پیش‌نویس — ساخته نمی‌شود (این مدل عمداً تا فاز ۵ اصلاً وجود ندارد)
#   4.5  ماشین‌حالت با جدول انتقال صریح:
#        draft → waiting_supply → legal_review → treasury_review →
#        receivables_review → pending_signature → approved → slips_issued →
#        closed / rejected (+ returned برای نقص، به کارشناس مالی)
#        تغییر مستقیم state بدون عبور از متد مجاز، در سطح مدل مسدود (SEC-016)
#   4.6  گردش سه‌ایستگاهی حقوقی→خزانه→وصول با سه خروجی مجزا:
#        تأیید / نقص مدارک (بازگشت به کارشناس مالی) / رد معامله (مختومه +
#        notify('deal.rejected') فوری) — G02
#   4.7  notify('trade_case.back_to_finance_supervisor') دقیقاً یک قدم پیش از
#        تغییر مسئول به سرپرست مالی؛ is_critical=1؛ گیرنده=requested_by +
#        alias اجباری case.result_to_ceo (UAT-07)
#   4.8  ★ گارد امضا در سطح سرور: ورود به pending_signature آزاد؛ خروج به
#        approved بدون signed_document مسدود با خطای صریح (فارسی از i18n) — G03
#   4.9  موتور مالی واحد itr.money.engine (models/money_engine.py) — تنها نقطهٔ
#        محاسبهٔ سود/مبالغ پایه؛ فرم و هر گزارش آینده از همین می‌خوانند (G18/FIN-005)
#   4.10 مدل itr.factory.shortfall (اسکلت؛ کلید یکتای شامل trade_case_item_id —
#        BR-121؛ منطق تکمیلی در فاز ۶)
#   4.11 Kanban بر اساس state با رنگ‌بندی وضعیت
#
# پوشش دو دغدغهٔ ثبت‌شدهٔ کارفرما (خارج از چک‌لیست رسمی، بدون اختلال در آن):
#   [C1] پایهٔ کارتابل/ارجاع/فضای کاری (بخش ۱۲ سند نیازمندی — فاز ۸ متولی اصلی):
#        - state machine صریح + current_owner_id + مهلت = ورودی «Unified Work
#          Queue» فاز ۸ (UX-011)؛ هیچ موتور Task دوم ساخته نشد (G18).
#        - ارجاع فقط از متد assign_to(): تغییر مالک + mail.activity (UX-004) +
#          رکورد append-only در itr.case.assignment.log + Chatter (بخش ۳: ارجاع).
#        - ارجاع سرپرست فقط به اعضای تیم خودش (SEC-004، از itr.supervisor.team
#          فاز ۳ — بازاستفاده، نه بازنویسی).
#   [C2] مدیریت ریسک فایل‌های مشترک با فاز ۳ (itr_core توسط 003.sh ساخته شده):
#        - هیچ فایل موجود فاز ۳ بازنویسی نمی‌شود؛ فقط فایل‌های «جدید» ساخته
#          می‌شوند و چهار فایل مشترک (__manifest__.py، models/__init__.py،
#          tests/__init__.py، security/ir.model.access.csv، i18n/fa_IR.po)
#          «افزایشی و idempotent» پچ می‌شوند (append/insert فقط اگر غایب باشند).
#        - پیش از هر تغییر: پشتیبان کامل DB (Q10) + کپی timestamp دار از
#          فایل‌های مشترک در docs/phase4-backup/ + امکان rollback با git.
#        - preflight «قرارداد فازهای قبل» را fingerprint می‌کند (کلاس‌ها/
#          xmlid ها/امضاها)؛ هر ناسازگاری = توقف فوری (پیوست ج نقشهٔ راه).
#        - پس از نصب، تست‌های خودکار فاز ۳ هم دوباره اجرا می‌شوند (test-tags
#          /itr_core شامل هر دو بخش) تا اثبات شود فاز ۴ فاز ۳ را نشکسته است.
#
# پیش‌نیاز: Gate 3 سبز (bash 003.sh → itr_core بخش اول نصب و installed)
#
# استفاده:
#   chmod +x 004.sh
#   bash 004.sh
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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase4-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase4-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase4-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase4-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase4-uat.log}"

MODULE="itr_core"
BASE_MODULE="itr_base"
NOTIFY_MODULE="itr_notify"
MOD_DIR="${CUSTOM_ADDONS}/${MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P4_BACKUP_DIR="${DOC_DIR}/phase4-backup"

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
step "0) preflight — Gate 3 سبز + fingerprint قرارداد فازهای ۱/۲/۳ (دغدغهٔ C2)"
# =============================================================================
[[ -d "${ODOO_DIR}" ]]            || err "ODOO_DIR یافت نشد: ${ODOO_DIR}"
[[ -f "${ODOO_DIR}/odoo-bin" ]]   || err "odoo-bin یافت نشد"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv یافت نشد: ${VENV_DIR}"
[[ -f "${CONF_FILE}" ]]           || err "odoo.conf یافت نشد: ${CONF_FILE} (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/.git" ]]  || err "مخزن Git addons سفارشی یافت نشد (ابتدا فاز ۰)"
[[ -d "${CUSTOM_ADDONS}/${BASE_MODULE}" ]]   || err "ماژول ${BASE_MODULE} یافت نشد (ابتدا فاز ۱)"
[[ -d "${CUSTOM_ADDONS}/${NOTIFY_MODULE}" ]] || err "ماژول ${NOTIFY_MODULE} یافت نشد (ابتدا فاز ۲)"
[[ -d "${MOD_DIR}" ]]                        || err "ماژول ${MODULE} یافت نشد (ابتدا فاز ۳)"
for t in psql git curl ss python3; do have "$t" || err "ابزار لازم غایب: $t"; done
db_exists "${DB_NAME}" || err "پایگاه‌دادهٔ ${DB_NAME} وجود ندارد (ابتدا فاز ۰)"

# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

ODOO_V="$("${ODOO_DIR}/odoo-bin" --version 2>/dev/null | head -n1 || echo 'unknown')"
echo "Odoo: ${ODOO_V}"
if echo "${ODOO_V}" | grep -qE '19\.[0-9]'; then
  gate "G4-00" "نسخهٔ Odoo 19 تأیید شد" "PASS" "${ODOO_V}"
else
  gate "G4-00" "نسخهٔ Odoo 19 تأیید شد" "FAIL" "نسخهٔ یافت‌شده: ${ODOO_V}"
  err "این اسکریپت فقط روی Odoo 19 اجرا می‌شود."
fi

BASE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${BASE_MODULE}'")"
NOTIFY_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${NOTIFY_MODULE}'")"
CORE_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
if [[ "${BASE_STATE}" == "installed" && "${NOTIFY_STATE}" == "installed" && "${CORE_STATE}" == "installed" ]]; then
  gate "G4-01" "پیش‌نیازهای فاز ۱/۲/۳ سبز هستند (Q02/Q08)" "PASS" "base=installed notify=installed core=installed"
else
  gate "G4-01" "پیش‌نیازهای فاز ۱/۲/۳ سبز هستند (Q02/Q08)" "FAIL" "base=${BASE_STATE:-missing} notify=${NOTIFY_STATE:-missing} core=${CORE_STATE:-missing}"
  err "طبق Q08، فازهای ۱ تا ۳ باید پیش از فاز ۴ نصب و سبز باشند."
fi

# ---- fingerprint قرارداد فازهای قبل (دغدغهٔ C2: «اسکریپت نسبت به قرارداد
# ---- فازهای قبل حساس است»؛ هر ناسازگاری = توقف اجباری، پیوست ج) --------------
CONTRACT_FAILS=()
contract() {  # $1=شرح $2=فایل $3=الگوی grep -E
  if grep -qE "$3" "$2" 2>/dev/null; then
    info "contract OK: $1"
  else
    CONTRACT_FAILS+=("$1 → الگوی «$3» در $2 یافت نشد")
  fi
}
contract "P1: سرویس اعتبارسنجی Guarded"           "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "_name = \"itr.validation.service\""
contract "P2: امضای notify(event_key, res_model, res_id, context)" "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_service.py" "def notify\(self, event_key, res_model=None, res_id=None, context=None\)"
contract "P2: مدل رویداد اعلان"                    "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_event.py" "_name = \"itr.notification.event\""
contract "P2: مدل alias رویداد"                    "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_alias.py" "_name = \"itr.notification.alias\""
contract "P3: سرویس نرخ ارز واحد"                  "${MOD_DIR}/models/itr_fx_service.py" "_name = \"itr.fx.service\""
contract "P3: امضای apply_fx(amount, from_currency, ...)" "${MOD_DIR}/models/itr_fx_service.py" "def apply_fx\(self, amount, from_currency, to_currency=None, date=None\)"
contract "P3: تیم سرپرستی + get_subordinate_users" "${MOD_DIR}/models/itr_supervisor_team.py" "def get_subordinate_users"
contract "P3: گروه CEO"                            "${MOD_DIR}/security/itr_core_groups.xml" "id=\"group_ceo\""
contract "P3: گروه سرپرست مالی"                    "${MOD_DIR}/security/itr_core_groups.xml" "id=\"group_finance_supervisor\""
contract "P3: منوی ریشهٔ itr_core"                 "${MOD_DIR}/views/itr_core_menus.xml" "id=\"menu_itr_core_root\""
contract "P3: مرجع manifest برای درج فایل‌های فاز ۴" "${MOD_DIR}/__manifest__.py" "views/itr_core_menus.xml"
GROUPS_OK=1
for g in group_ceo group_document_signer group_finance_supervisor group_finance_user \
         group_legal_reviewer group_treasury_user group_receivables_user; do
  GID="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core' AND name='${g}'")"
  [[ "${GID}" == "1" ]] || { GROUPS_OK=0; CONTRACT_FAILS+=("گروه ${g} در دیتابیس یافت نشد"); }
done
if [[ ${#CONTRACT_FAILS[@]} -eq 0 && ${GROUPS_OK} -eq 1 ]]; then
  gate "G4-02" "fingerprint قرارداد فازهای ۱/۲/۳ منطبق است (C2 / پیوست ج)" "PASS" "11 contract + 7 group"
else
  gate "G4-02" "fingerprint قرارداد فازهای ۱/۲/۳ منطبق است (C2 / پیوست ج)" "FAIL" "$(printf '%s | ' "${CONTRACT_FAILS[@]}")"
  err "قرارداد فازهای قبل مطابق فرض فاز ۴ نیست — طبق پیوست ج، فاز متوقف شد. هیچ فایلی تغییر نکرد."
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
  gate "G4-03" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "SKIP_BACKUP=1"
elif [[ -x "${OPS_DIR}/backup.sh" ]]; then
  BK_OUT="$(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}" 2>/dev/null || true)"
  BK_DUMP="$(echo "${BK_OUT}" | head -n1)"
  if [[ -s "${BK_DUMP:-/nonexistent}" ]]; then
    gate "G4-03" "پشتیبان پیش از ارتقا گرفته شد" "PASS" "$(basename "${BK_DUMP}")"
  else
    gate "G4-03" "پشتیبان پیش از ارتقا گرفته شد" "FAIL" "ops/backup.sh خروجی معتبر نداد"
  fi
else
  gate "G4-03" "پشتیبان پیش از ارتقا گرفته شد" "WARN" "ops/backup.sh یافت نشد"
fi

# پشتیبان فایل‌های مشترک فاز ۳ که فاز ۴ آن‌ها را «افزایشی» پچ می‌کند (C2)
TS="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${P4_BACKUP_DIR}/${TS}"
for f in "__manifest__.py" "models/__init__.py" "tests/__init__.py" \
         "security/ir.model.access.csv" "i18n/fa_IR.po" "i18n/fa.po"; do
  if [[ -f "${MOD_DIR}/${f}" ]]; then
    mkdir -p "${P4_BACKUP_DIR}/${TS}/$(dirname "${f}")"
    cp -f "${MOD_DIR}/${f}" "${P4_BACKUP_DIR}/${TS}/${f}"
  fi
done
log "کپی امن فایل‌های مشترک در ${P4_BACKUP_DIR}/${TS} (rollback: git checkout یا همین کپی‌ها)"

# =============================================================================
step "3) ساخت فایل‌های *جدید* فاز ۴ (هیچ فایل فاز ۳ بازنویسی نمی‌شود — C2)"
# =============================================================================
mkdir -p "${MOD_DIR}"/{models,security,data,views,i18n,tests}
mkdir -p "${OPS_DIR}/verify" "${DOC_DIR}"
find "${MOD_DIR}" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "${MOD_DIR}" -name '*.pyc' -delete 2>/dev/null || true

# ------------------------------------------------- models/money_engine.py --
write_utf8 "${MOD_DIR}/models/money_engine.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""THE single money engine of the whole project (checklist 4.9 / SRS 8-4).

FIN-005 / G18: profit and base amounts are computed HERE and only here.
The trade case form, every dashboard card and every phase-9 report must call
this service; a second parallel formula anywhere in the repository turns the
phase gate red (grep-enforced by the phase script).

Phase 4 scope: purchase/sales base totals and estimated profit of a trade
case. total_operational_cost is 0 until phase 6 wires itr.cost.line in
(FIN-003: a payment is a settlement, never a second cost).
"""
from odoo import api, models


class ItrMoneyEngine(models.AbstractModel):
    _name = "itr.money.engine"
    _description = "Iran Trade Money Engine"

    @api.model
    def item_side_base(self, item, side):
        """Base (IRR) amount of one side ('purchase' or 'sale') of one item.

        Uses the LOCKED rate when the item is locked (G12/FIN-014), otherwise
        resolves through the single FX service of phase 3 (never a second
        engine). Returns 0.0 when the side does not apply to the row_kind.
        """
        if side == "purchase" and item.row_kind == "sale":
            return 0.0
        if side == "sale" and item.row_kind == "purchase":
            return 0.0
        amount = item.purchase_amount if side == "purchase" else item.sale_amount
        currency = item.purchase_currency_id if side == "purchase" else item.sale_currency_id
        locked_rate = item.purchase_fx_rate if side == "purchase" else item.sale_fx_rate
        if not amount:
            return 0.0
        if item.rate_locked and locked_rate:
            return float(amount) * float(locked_rate)
        if not currency:
            return float(amount)
        try:
            fx = self.env["itr.fx.service"].apply_fx(amount, currency)
            return fx["base_amount"]
        except Exception:  # noqa: BLE001 - a missing rate must not break a draft form
            return 0.0

    @api.model
    def case_totals(self, case):
        """The one and only financial summary of a trade case.

        Returns dict(contract_tonnage, purchase_base, sales_base,
        operational_cost, estimated_profit). Every consumer (form roll-up,
        phase 8 dashboard, phase 9 report) reads THESE numbers (UAT-08).
        """
        contract_tonnage = 0.0
        purchase_base = 0.0
        sales_base = 0.0
        for item in case.item_ids:
            contract_tonnage += item.contract_tonnage or 0.0
            purchase_base += self.item_side_base(item, "purchase")
            sales_base += self.item_side_base(item, "sale")
        operational_cost = 0.0  # phase 6: freight+customs+clearance+insurance+origin+other
        return {
            "contract_tonnage": contract_tonnage,
            "purchase_base": purchase_base,
            "sales_base": sales_base,
            "operational_cost": operational_cost,
            "estimated_profit": sales_base - purchase_base - operational_cost,
        }
PYEOF

# --------------------------------------------- models/itr_trade_case_item.py
write_utf8 "${MOD_DIR}/models/itr_trade_case_item.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Trade case item (checklist 4.3 / SRS section 3 + G11 + G12).

* One row = one goods line with its OWN dimensions, thickness, contract
  tonnage and its OWN purchase/sale money events.
* row_kind is the field every future report must branch on (G11): a mixed
  case is split by the kind of each row, never by a single header field.
* Currency is a property of the money event, not of the case (G12): each
  side carries the standard four fields amount/currency/rate/base and a
  rate_locked flag (FIN-011..FIN-014).
* Three independent tonnages (SRS glossary): contract (this phase),
  reserved (phase 5) and effective (phase 6) - the last two are read-only
  skeleton fields here so phase 9 reports (G10) have a stable base.
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

ROW_KINDS = [
    ("purchase", "Purchase row"),
    ("sale", "Sale row"),
    ("both", "Purchase & sale row"),
]


class ItrTradeCaseItem(models.Model):
    _name = "itr.trade.case.item"
    _description = "Trade Case Item"
    _order = "case_id, sequence, id"

    case_id = fields.Many2one(
        "itr.trade.case", string="Trade case", required=True,
        ondelete="cascade", index=True,
    )
    sequence = fields.Integer(string="Sequence", default=10)
    name = fields.Char(string="Goods description", required=True)
    product_id = fields.Many2one(
        "product.product", string="Product (catalogue)", ondelete="restrict",
        help="Optional link to the standard Odoo catalogue (Q13); the free "
             "description stays the operational source of truth.",
    )
    row_kind = fields.Selection(
        ROW_KINDS, string="Row kind", required=True, default="both",
        help="G11: every financial report decides purchase/sale per ROW, "
             "never from a single header field.",
    )

    thickness_mm = fields.Float(string="Thickness (mm)")
    width_cm = fields.Float(string="Width (cm)")
    length_cm = fields.Float(string="Length (cm)")
    dimension_note = fields.Char(string="Dimension note")

    contract_tonnage = fields.Float(string="Contract tonnage", required=True)
    reserved_tonnage = fields.Float(
        string="Reserved tonnage", readonly=True,
        help="Sum allocated to open loadings - written by phase 5 only.",
    )
    effective_tonnage = fields.Float(
        string="Effective tonnage", readonly=True,
        help="Confirmed weighbridge net weight - written by phase 6 only "
             "(OPS-023: never overwritten by a waybill).",
    )
    remaining_tonnage = fields.Float(
        string="Remaining tonnage", compute="_compute_remaining", store=True,
        help="BR-005: contract - effective. The ONLY allowed formula.",
    )

    # --- purchase money event (G12: four standard fields + lock) ----------
    purchase_price_unit = fields.Float(string="Purchase rate / ton")
    purchase_currency_id = fields.Many2one(
        "res.currency", string="Purchase currency",
        default=lambda self: self.env.company.currency_id,
    )
    purchase_amount = fields.Float(
        string="Purchase amount", compute="_compute_amounts", store=True)
    purchase_fx_rate = fields.Float(string="Purchase conversion rate", readonly=True)
    purchase_base_amount = fields.Float(
        string="Purchase base amount (IRR)", compute="_compute_base_amounts", store=True)

    # --- sale money event --------------------------------------------------
    sale_price_unit = fields.Float(string="Sale rate / ton")
    sale_currency_id = fields.Many2one(
        "res.currency", string="Sale currency",
        default=lambda self: self.env.company.currency_id,
    )
    sale_amount = fields.Float(
        string="Sale amount", compute="_compute_amounts", store=True)
    sale_fx_rate = fields.Float(string="Sale conversion rate", readonly=True)
    sale_base_amount = fields.Float(
        string="Sale base amount (IRR)", compute="_compute_base_amounts", store=True)

    rate_locked = fields.Boolean(
        string="Rates locked", readonly=True,
        help="FIN-014: signature locks the rates of the items present at that "
             "moment; later money events lock their own rate when they happen.",
    )
    note = fields.Char(string="Notes")

    @api.depends("contract_tonnage", "effective_tonnage")
    def _compute_remaining(self):
        for item in self:
            item.remaining_tonnage = (item.contract_tonnage or 0.0) - (item.effective_tonnage or 0.0)

    @api.depends("contract_tonnage", "purchase_price_unit", "sale_price_unit")
    def _compute_amounts(self):
        for item in self:
            tonnage = item.contract_tonnage or 0.0
            item.purchase_amount = tonnage * (item.purchase_price_unit or 0.0)
            item.sale_amount = tonnage * (item.sale_price_unit or 0.0)

    @api.depends("purchase_amount", "sale_amount", "purchase_currency_id",
                 "sale_currency_id", "rate_locked", "purchase_fx_rate", "sale_fx_rate")
    def _compute_base_amounts(self):
        engine = self.env["itr.money.engine"]
        for item in self:
            item.purchase_base_amount = engine.item_side_base(item, "purchase")
            item.sale_base_amount = engine.item_side_base(item, "sale")

    @api.constrains("contract_tonnage")
    def _check_tonnage(self):
        for item in self:
            if item.contract_tonnage <= 0:
                raise ValidationError(
                    _("The contract tonnage of item '%(name)s' must be greater than zero.",
                      name=item.name)
                )

    @api.constrains("row_kind", "purchase_price_unit", "sale_price_unit")
    def _check_row_kind_rates(self):
        for item in self:
            if item.row_kind in ("purchase", "both") and item.purchase_price_unit < 0:
                raise ValidationError(_("The purchase rate cannot be negative."))
            if item.row_kind in ("sale", "both") and item.sale_price_unit < 0:
                raise ValidationError(_("The sale rate cannot be negative."))

    def lock_rates(self):
        """FIN-014: called by the signature confirmation of the parent case.

        Locks ONLY the items existing at that moment; each side resolves its
        own rate through the single FX service (G18).
        """
        fx = self.env["itr.fx.service"]
        for item in self:
            if item.rate_locked:
                continue
            vals = {"rate_locked": True}
            if item.purchase_amount and item.purchase_currency_id:
                vals["purchase_fx_rate"] = fx.resolve_rate(item.purchase_currency_id)
            if item.sale_amount and item.sale_currency_id:
                vals["sale_fx_rate"] = fx.resolve_rate(item.sale_currency_id)
            item.write(vals)
        return True
PYEOF

# --------------------------------------------------- models/itr_trade_case.py
write_utf8 "${MOD_DIR}/models/itr_trade_case.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""The trade case (checklist 4.1 .. 4.8 / SRS sections 3, 6, 7).

State machine (LOCKED - G10/Q11, renaming needs a formal migration):

    draft -> waiting_supply -> legal_review -> treasury_review ->
    receivables_review -> pending_signature -> approved -> slips_issued ->
    closed / rejected (+ returned: document deficiency, back to the finance
    specialist - G02: a REJECTED case is terminal and never returns).

Iron guards implemented at MODEL level (not only UI - SEC-016):
* the state field can only move through _do_transition() (a direct write,
  from the UI or a raw RPC call, is refused);
* every transition method checks the role of the REAL user on the server;
* requested_by accepts only members of group_ceo (client domain + server
  constraint) and is frozen after the first save (checklist 4.2);
* leaving pending_signature without signed_document is blocked (4.8/G03);
* pattern B never creates a sales slip - the itr.sales.slip model does not
  even exist before phase 5 (4.4/BR-004);
* notify('trade_case.back_to_finance_supervisor') fires exactly ONE step
  before the case lands on the finance supervisor desk (4.7/UAT-07);
* deal rejection fires notify('deal.rejected') immediately (4.6/G02).

Cartable foundation (owner concern C1 - basis for phase 8, no second task
engine, G18): current_owner_id + owner_deadline + assign_to() which is the
ONLY legal way to hand work over (SRS glossary: Assignment = owner change +
cartable record + notification + history). Phase 8 builds its Unified Work
Queue on the state machine + these fields; it must NOT invent another one.
"""
from odoo import _, api, fields, models
from odoo.exceptions import UserError, ValidationError

# G10 / Q11: locked state names - registered in ARCHITECTURE_DECISIONS.md
TRADE_STATES = [
    ("draft", "Draft"),
    ("waiting_supply", "Waiting for supply"),
    ("legal_review", "Legal review"),
    ("treasury_review", "Treasury review"),
    ("receivables_review", "Receivables review"),
    ("pending_signature", "Pending physical signature"),
    ("approved", "Approved (signed)"),
    ("slips_issued", "Sales slips issued"),
    ("closed", "Closed"),
    ("rejected", "Rejected (terminal)"),
    ("returned", "Returned for completion"),
]

# checklist 4.5: the explicit transition table - anything else is refused
ALLOWED_TRANSITIONS = {
    "draft": {"legal_review", "waiting_supply"},
    "waiting_supply": {"legal_review"},
    "legal_review": {"treasury_review", "returned", "rejected"},
    "treasury_review": {"receivables_review", "returned", "rejected"},
    "receivables_review": {"pending_signature", "returned", "rejected"},
    "returned": {"legal_review"},
    "pending_signature": {"approved"},
    "approved": {"slips_issued"},
    "slips_issued": {"closed"},
    "rejected": set(),   # G02: terminal, the case never comes back
    "closed": set(),
}

DEAL_PATTERNS = [
    ("buy_first", "Pattern A - buy first"),
    ("sell_first", "Pattern B - sell first (pre-sale)"),
]

REVIEW_RESULTS = [
    ("pending", "Pending"),
    ("approved", "Approved"),
    ("returned", "Documents incomplete"),
    ("rejected", "Deal rejected"),
]

STATE_ENGINE_CTX = "itr_trade_state_engine"


class ItrTradeCase(models.Model):
    _name = "itr.trade.case"
    _description = "Trade Case"
    _inherit = ["mail.thread", "mail.activity.mixin"]
    _order = "id desc"

    # ------------------------------------------------------------ identity
    name = fields.Char(
        string="Case number", required=True, copy=False, readonly=True,
        index=True, default=lambda self: _("New"),
    )
    company_id = fields.Many2one(
        "res.company", string="Company", required=True, index=True,
        default=lambda self: self.env.company,
    )
    requested_by = fields.Many2one(
        "res.users", string="Ordered by (CEO)", required=True, tracking=True,
        domain=lambda self: [("group_ids", "in",
                              [self.env.ref("itr_core.group_ceo").id])],
        help="Checklist 4.2: only a member of group_ceo; frozen after the "
             "first save (client domain + server constraint).",
    )
    deal_pattern = fields.Selection(
        DEAL_PATTERNS, string="Deal pattern", required=True,
        default="buy_first", tracking=True,
    )
    state = fields.Selection(
        TRADE_STATES, string="State", required=True, default="draft",
        index=True, tracking=True, copy=False,
    )
    review_round = fields.Integer(
        string="Review round", default=0, readonly=True, copy=False,
        help="Incremented on every (re)submission to the review chain; used "
             "as the notification occurrence discriminator.",
    )

    # -------------------------------------------------- parties / logistics
    factory_id = fields.Many2one(
        "res.partner", string="Factory / origin", tracking=True,
        domain=[("is_factory", "=", True)],
    )
    buyer_id = fields.Many2one(
        "res.partner", string="Buyer (pattern B commitment)", tracking=True,
        help="BR-004: in pattern B the sale commitment lives on the case "
             "itself until the signed purchase document is uploaded.",
    )
    border_id = fields.Many2one("itr.border", string="Exit border")
    destination = fields.Char(string="Destination")
    item_ids = fields.One2many("itr.trade.case.item", "case_id", string="Items")

    # ------------------------------------ proforma anchors (XLS-031 basis)
    proforma_purchase_ref = fields.Char(string="Purchase proforma reference")
    proforma_sales_ref = fields.Char(string="Sales proforma reference")

    # -------------------------------------------------- review audit trail
    legal_result = fields.Selection(REVIEW_RESULTS, default="pending",
                                    string="Legal result", readonly=True, copy=False)
    legal_by_id = fields.Many2one("res.users", string="Legal reviewer", readonly=True, copy=False)
    legal_on = fields.Datetime(string="Legal decided on", readonly=True, copy=False)
    treasury_result = fields.Selection(REVIEW_RESULTS, default="pending",
                                       string="Treasury result", readonly=True, copy=False)
    treasury_by_id = fields.Many2one("res.users", string="Treasury reviewer", readonly=True, copy=False)
    treasury_on = fields.Datetime(string="Treasury decided on", readonly=True, copy=False)
    receivables_result = fields.Selection(REVIEW_RESULTS, default="pending",
                                          string="Receivables result", readonly=True, copy=False)
    receivables_by_id = fields.Many2one("res.users", string="Receivables reviewer", readonly=True, copy=False)
    receivables_on = fields.Datetime(string="Receivables decided on", readonly=True, copy=False)
    last_return_reason = fields.Text(string="Last deficiency reason", readonly=True, copy=False)
    rejection_reason = fields.Text(string="Rejection reason", readonly=True, copy=False)

    # -------------------------------------------------- signature (4.8/G03)
    signed_document = fields.Binary(string="Signed document scan", attachment=True, copy=False)
    signed_document_filename = fields.Char(string="Signed document file name", copy=False)
    signed_by_id = fields.Many2one("res.users", string="Signature registered by",
                                   readonly=True, copy=False)
    signed_on = fields.Datetime(string="Signature registered on", readonly=True, copy=False)

    # ------------------------------------- cartable foundation (C1 / UX-011)
    current_owner_id = fields.Many2one(
        "res.users", string="Current owner", index=True, tracking=True, copy=False,
        help="The user whose desk the case sits on right now. Phase 8 builds "
             "the unified work queue on this field + the state machine (G18).",
    )
    owner_deadline = fields.Datetime(string="Owner deadline", copy=False)
    assignment_log_ids = fields.One2many(
        "itr.case.assignment.log", "case_id", string="Assignment history", readonly=True)

    # ------------------------------------ read-only roll-ups (4.9 -> phase 9)
    total_contract_tonnage = fields.Float(
        string="Total contract tonnage", compute="_compute_totals", store=True)
    purchase_total_base = fields.Float(
        string="Total purchase (IRR)", compute="_compute_totals", store=True)
    sales_total_base = fields.Float(
        string="Total sales (IRR)", compute="_compute_totals", store=True)
    estimated_profit_base = fields.Float(
        string="Estimated profit (IRR)", compute="_compute_totals", store=True,
        help="FIN-005: computed ONLY by itr.money.engine - the same number "
             "the phase 9 report and the phase 8 dashboard must show (UAT-08).",
    )

    # =====================================================================
    # computes / constraints
    # =====================================================================
    @api.depends("item_ids.contract_tonnage", "item_ids.purchase_base_amount",
                 "item_ids.sale_base_amount", "item_ids.row_kind",
                 "item_ids.rate_locked")
    def _compute_totals(self):
        engine = self.env["itr.money.engine"]
        for case in self:
            totals = engine.case_totals(case)
            case.total_contract_tonnage = totals["contract_tonnage"]
            case.purchase_total_base = totals["purchase_base"]
            case.sales_total_base = totals["sales_base"]
            case.estimated_profit_base = totals["estimated_profit"]

    @api.constrains("requested_by")
    def _check_requested_by_is_ceo(self):
        """4.2: the server constraint - a raw RPC call is refused too."""
        for case in self:
            if case.requested_by and not case.requested_by.has_group("itr_core.group_ceo"):
                raise ValidationError(
                    _("Only a CEO (group_ceo member) can be selected as the "
                      "orderer of a trade case.")
                )

    # =====================================================================
    # create / write guards (SEC-016 + 4.2 lock)
    # =====================================================================
    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if not vals.get("name") or vals.get("name") == _("New"):
                vals["name"] = self.env["ir.sequence"].next_by_code("itr.trade.case") or _("New")
            if vals.get("state") and vals["state"] != "draft":
                raise UserError(
                    _("A trade case always starts in draft; the state only "
                      "moves through its official transition methods.")
                )
            vals.setdefault("current_owner_id", self.env.user.id)
        return super().create(vals_list)

    def write(self, vals):
        # SEC-016 / checklist 4.5: no direct state write - UI, RPC or sudo
        if "state" in vals and not self.env.context.get(STATE_ENGINE_CTX):
            raise UserError(
                _("The case state can only change through its official "
                  "transition actions, never by writing the field directly.")
            )
        # checklist 4.2: requested_by frozen after the first save
        if "requested_by" in vals:
            for case in self:
                if case.requested_by and vals["requested_by"] != case.requested_by.id:
                    raise UserError(
                        _("The orderer of the case is locked after the first "
                          "save and can never be changed.")
                    )
        return super().write(vals)

    def unlink(self):
        for case in self:
            if case.state != "draft":
                raise UserError(
                    _("Only a draft case can be deleted; every other state is "
                      "part of the audit trail (OPS-027)."))
        return super().unlink()

    # =====================================================================
    # the single transition engine (checklist 4.5)
    # =====================================================================
    def _do_transition(self, new_state):
        for case in self:
            allowed = ALLOWED_TRANSITIONS.get(case.state, set())
            if new_state not in allowed:
                raise UserError(
                    _("Illegal state change: %(old)s -> %(new)s is not in the "
                      "official transition table of the trade case.",
                      old=case.state, new=new_state)
                )
            case.with_context(**{STATE_ENGINE_CTX: True}).write({"state": new_state})
            case.message_post(body=_(
                "State changed to <b>%(state)s</b> by %(user)s.",
                state=dict(TRADE_STATES).get(new_state, new_state),
                user=self.env.user.display_name,
            ))
        return True

    def _require_group(self, xmlid, action_label):
        if self.env.su:
            raise UserError(
                _("Business transitions are never executed as superuser (G01/Q03)."))
        if not self.env.user.has_group(xmlid):
            raise UserError(
                _("Access refused: the action '%(action)s' requires the role "
                  "%(group)s.", action=action_label, group=xmlid)
            )

    def _forbid_self_approval(self):
        """SEC-015 skeleton: the creator never approves his own case."""
        for case in self:
            if case.create_uid == self.env.user:
                raise UserError(
                    _("Segregation of duties: the user who created the case "
                      "cannot approve it (SEC-015)."))

    def _notify(self, event_key, extra=None):
        """The ONLY alert path (NOT-001) - notify() never raises."""
        context = {"occurrence_id": "tc-%s-%s-r%s" % (self.id, event_key, self.review_round)}
        context.update(extra or {})
        return self.env["itr.notification.service"].notify(
            event_key, self._name, self.id, context)

    def _hand_over_to_group(self, group_xmlid, summary):
        """Move the desk to the least-loaded member of a group (G15 basis)."""
        group = self.env.ref(group_xmlid, raise_if_not_found=False)
        if not group:
            return False
        blocked = self.env["itr.notification.event"]._blocked_user_ids()
        users = group.users if "users" in group._fields else group.user_ids
        candidates = [u for u in users if u.active and u.id not in blocked]
        if not candidates:
            return False
        loads = {
            u.id: self.search_count([
                ("current_owner_id", "=", u.id),
                ("state", "not in", ("closed", "rejected")),
            ])
            for u in candidates
        }
        target = min(candidates, key=lambda u: (loads[u.id], u.id))
        self._assign_internal(target, summary)
        return target

    # =====================================================================
    # workflow actions (4.4 / 4.6 / 4.7 / 4.8)
    # =====================================================================
    def action_submit(self):
        """draft -> legal_review (A) | waiting_supply (B) - BR-003."""
        for case in self:
            if not case.item_ids:
                raise UserError(_("A case cannot enter the workflow without at least one item."))
            if case.state != "draft":
                raise UserError(_("Only a draft case can be submitted."))
            case.with_context(**{STATE_ENGINE_CTX: True}).write(
                {"review_round": case.review_round + 1})
            if case.deal_pattern == "sell_first":
                # BR-004: no sales slip, not even a draft - the model itself
                # does not exist before phase 5; the commitment stays here.
                case._do_transition("waiting_supply")
                case._notify("case.parked_waiting_supply")
            else:
                case._start_review_chain()
        return True

    def action_supply_ready(self):
        """waiting_supply -> legal_review, once the purchase rate is final."""
        for case in self:
            if case.state != "waiting_supply":
                raise UserError(_("Only a case waiting for supply can be released."))
            missing = case.item_ids.filtered(
                lambda i: i.row_kind in ("purchase", "both") and not i.purchase_price_unit)
            if missing:
                raise UserError(
                    _("The purchase rate of every purchase row must be final "
                      "before the review chain starts (BR-003 pattern B)."))
            case._start_review_chain()
        return True

    def _start_review_chain(self):
        self.ensure_one()
        self.with_context(**{STATE_ENGINE_CTX: True}).write({
            "legal_result": "pending", "treasury_result": "pending",
            "receivables_result": "pending",
        })
        self._do_transition("legal_review")
        self._hand_over_to_group("itr_core.group_legal_reviewer",
                                 _("Legal review of the trade case"))

    # ---- the three-station chain (4.6) ------------------------------------
    def _station_decide(self, station, decision, reason=None):
        """One shared, guarded implementation for the three review stations."""
        station_map = {
            "legal": ("itr_core.group_legal_reviewer", "legal_review",
                      "treasury_review", "case.legal_rejected",
                      "itr_core.group_treasury_user"),
            "treasury": ("itr_core.group_treasury_user", "treasury_review",
                         "receivables_review", "case.treasury_rejected",
                         "itr_core.group_receivables_user"),
            "receivables": ("itr_core.group_receivables_user", "receivables_review",
                            "pending_signature", "case.receivables_rejected",
                            None),
        }
        group_xmlid, expected_state, next_state, reject_event, next_group = station_map[station]
        for case in self:
            case._require_group(group_xmlid, station)
            case._forbid_self_approval() if decision == "approved" else None
            if case.state != expected_state:
                raise UserError(
                    _("This decision belongs to the state %(state)s; the case "
                      "is elsewhere.", state=expected_state))
            now = fields.Datetime.now()
            audit = {
                "%s_result" % station: decision,
                "%s_by_id" % station: self.env.user.id,
                "%s_on" % station: now,
            }
            if decision == "returned":
                if not (reason or "").strip():
                    raise UserError(_("A deficiency return requires a mandatory reason."))
                audit["last_return_reason"] = reason
                case.with_context(**{STATE_ENGINE_CTX: True}).write(audit)
                case._do_transition("returned")
                # G02: deficiency goes BACK to the finance specialist, the case stays alive
                case._hand_over_to_group("itr_core.group_finance_user",
                                         _("Complete the deficient documents and resubmit"))
                case.message_post(body=_("Documents incomplete at %(st)s station: %(r)s",
                                         st=station, r=reason))
            elif decision == "rejected":
                if not (reason or "").strip():
                    raise UserError(_("A deal rejection requires a mandatory reason."))
                audit["rejection_reason"] = reason
                case.with_context(**{STATE_ENGINE_CTX: True}).write(audit)
                case._do_transition("rejected")
                # G02: terminal + immediate SMS to the CEO; never back to finance
                case._notify(reject_event, {"reason": reason})
                case._notify("deal.rejected", {"reason": reason})
                case.with_context(**{STATE_ENGINE_CTX: True}).write({"current_owner_id": False})
            else:  # approved
                case.with_context(**{STATE_ENGINE_CTX: True}).write(audit)
                if station == "receivables":
                    # ★ 4.7 / UAT-07: EXACTLY one step before the finance
                    # supervisor desk - before the transition and the handover.
                    case._notify("trade_case.back_to_finance_supervisor")
                    case._do_transition(next_state)
                    case._hand_over_to_group("itr_core.group_finance_supervisor",
                                             _("Print the Sepidar form, obtain the physical "
                                               "signature and upload the scan"))
                else:
                    case._do_transition(next_state)
                    case._hand_over_to_group(next_group,
                                             _("Specialist review of the trade case"))
        return True

    def action_legal_approve(self):
        return self._station_decide("legal", "approved")

    def action_legal_return(self, reason=None):
        return self._station_decide("legal", "returned",
                                    reason or self.env.context.get("itr_reason"))

    def action_legal_reject(self, reason=None):
        return self._station_decide("legal", "rejected",
                                    reason or self.env.context.get("itr_reason"))

    def action_treasury_approve(self):
        return self._station_decide("treasury", "approved")

    def action_treasury_return(self, reason=None):
        return self._station_decide("treasury", "returned",
                                    reason or self.env.context.get("itr_reason"))

    def action_treasury_reject(self, reason=None):
        return self._station_decide("treasury", "rejected",
                                    reason or self.env.context.get("itr_reason"))

    def action_receivables_approve(self):
        return self._station_decide("receivables", "approved")

    def action_receivables_return(self, reason=None):
        return self._station_decide("receivables", "returned",
                                    reason or self.env.context.get("itr_reason"))

    def action_receivables_reject(self, reason=None):
        return self._station_decide("receivables", "rejected",
                                    reason or self.env.context.get("itr_reason"))

    def action_resubmit(self):
        """returned -> legal_review (the corrected file re-enters the chain)."""
        for case in self:
            case._require_group("itr_core.group_finance_user", "resubmit")
            if case.state != "returned":
                raise UserError(_("Only a returned case can be resubmitted."))
            case.with_context(**{STATE_ENGINE_CTX: True}).write(
                {"review_round": case.review_round + 1})
            case._start_review_chain()
        return True

    # ---- signature guard (4.8 / G03) ---------------------------------------
    def action_confirm_signed(self):
        """pending_signature -> approved. ENTER free, EXIT needs the scan."""
        for case in self:
            if not (self.env.user.has_group("itr_core.group_finance_supervisor")
                    or self.env.user.has_group("itr_core.group_document_signer")):
                raise UserError(
                    _("Only the finance supervisor or a document signer may "
                      "confirm the physical signature."))
            if self.env.su:
                raise UserError(
                    _("Business transitions are never executed as superuser (G01/Q03)."))
            if case.state != "pending_signature":
                raise UserError(_("The case is not waiting for a signature."))
            if not case.signed_document:
                raise UserError(
                    _("Leaving the signature step without the scanned, signed "
                      "document is blocked (G03). Upload the scan first."))
            case.with_context(**{STATE_ENGINE_CTX: True}).write({
                "signed_by_id": self.env.user.id,
                "signed_on": fields.Datetime.now(),
            })
            # FIN-014: signature locks the rates of the items of this version
            case.item_ids.lock_rates()
            case._do_transition("approved")
            case._notify("case.signed_and_uploaded")
            # G03: only now the finance specialist may issue the sales slips (phase 5)
            case._hand_over_to_group("itr_core.group_finance_user",
                                     _("Issue the sales slips (after signature)"))
        return True

    def mark_slips_issued(self):
        """approved -> slips_issued. Called by phase 5 (itr.sales.slip)."""
        for case in self:
            case._require_group("itr_core.group_finance_user", "mark_slips_issued")
            case._do_transition("slips_issued")
        return True

    # =====================================================================
    # assignment / cartable foundation (C1 - SRS glossary + UX-004)
    # =====================================================================
    def _assign_internal(self, user, reason):
        """Owner change + activity + append-only log + chatter (never less)."""
        self.ensure_one()
        blocked = self.env["itr.notification.event"]._blocked_user_ids()
        if not user or not user.active or user.id in blocked:
            raise UserError(
                _("Administrator, OdooBot or an archived user can never own a "
                  "case (SEC-002)."))
        previous = self.current_owner_id
        days = int(self.env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
            "itr_core.default_assignment_days", "2"))
        deadline = fields.Datetime.add(fields.Datetime.now(), days=days)
        self.with_context(**{STATE_ENGINE_CTX: True}).write({
            "current_owner_id": user.id,
            "owner_deadline": deadline,
        })
        self.env["itr.case.assignment.log"].create({
            "case_id": self.id,
            "from_user_id": previous.id if previous else False,
            "to_user_id": user.id,
            "reason": reason or _("Assignment"),
            "state_at_assignment": self.state,
        })
        self.activity_schedule(
            "mail.mail_activity_data_todo",
            user_id=user.id,
            summary=reason or _("Trade case assignment"),
            date_deadline=fields.Date.to_date(deadline),
        )
        self.message_post(body=_(
            "Assigned to <b>%(to)s</b> by %(by)s. Reason: %(reason)s",
            to=user.display_name, by=self.env.user.display_name,
            reason=reason or "-",
        ))
        return True

    def assign_to(self, user, reason=None):
        """The ONLY legal reassignment path (SRS: the word 'release' is banned).

        A supervisor may only assign inside his own team (SEC-004); the CEO
        and the financial manager are unrestricted.
        """
        self.ensure_one()
        if not (reason or "").strip():
            raise UserError(_("A reassignment always requires a mandatory reason."))
        if self.state in ("rejected", "closed"):
            raise UserError(_("A terminal case cannot be reassigned."))
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
PYEOF

# ------------------------------------- models/itr_case_assignment_log.py --
write_utf8 "${MOD_DIR}/models/itr_case_assignment_log.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Append-only assignment history (owner concern C1 / SRS glossary + REQ-002).

'Assignment = owner change + cartable record + notification + history'.
This model is that cartable record: pure history, deliberately NOT a second
task queue (G18) - phase 8 builds the Unified Work Queue on the state machine
and current_owner_id, and reads this log for the audit trail.
"""
from odoo import _, fields, models
from odoo.exceptions import UserError


class ItrCaseAssignmentLog(models.Model):
    _name = "itr.case.assignment.log"
    _description = "Trade Case Assignment Log"
    _order = "id desc"

    case_id = fields.Many2one("itr.trade.case", string="Trade case",
                              required=True, ondelete="cascade", index=True)
    from_user_id = fields.Many2one("res.users", string="From", readonly=True,
                                   ondelete="restrict")
    to_user_id = fields.Many2one("res.users", string="To", required=True,
                                 readonly=True, ondelete="restrict", index=True)
    reason = fields.Text(string="Reason", required=True, readonly=True)
    state_at_assignment = fields.Char(string="State at assignment", readonly=True)
    assigned_by_id = fields.Many2one(
        "res.users", string="Assigned by", required=True, readonly=True,
        default=lambda self: self.env.user)
    assigned_on = fields.Datetime(
        string="Assigned on", required=True, readonly=True,
        default=fields.Datetime.now)

    def write(self, vals):
        raise UserError(_("Assignment log records are append-only and cannot be modified."))

    def unlink(self):
        raise UserError(_("Assignment log records are append-only and cannot be deleted."))
PYEOF

# ----------------------------------------- models/itr_factory_shortfall.py --
write_utf8 "${MOD_DIR}/models/itr_factory_shortfall.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Factory shortfall ledger - SKELETON (checklist 4.10 / SRS 10-3).

Phase 4 delivers the data structure with the CORRECT unique key (BR-121: the
key includes trade_case_item_id, never just case+product, otherwise two rows
of the same goods with different dimensions/prices would merge into one
claim). The automatic creation on manual close and the partial settlements
(BR-122) are wired in phase 6.
"""
from odoo import _, api, fields, models
from odoo.exceptions import ValidationError

SHORTFALL_STATES = [
    ("open", "Open"),
    ("partially_settled", "Partially settled"),
    ("settled", "Settled"),
]


class ItrFactoryShortfall(models.Model):
    _name = "itr.factory.shortfall"
    _description = "Factory Shortfall Ledger"
    _inherit = ["mail.thread"]
    _order = "id desc"

    supplier_id = fields.Many2one("res.partner", string="Factory / supplier",
                                  required=True, domain=[("is_factory", "=", True)],
                                  index=True, tracking=True)
    trade_case_id = fields.Many2one("itr.trade.case", string="Trade case",
                                    required=True, ondelete="restrict", index=True)
    trade_case_item_id = fields.Many2one(
        "itr.trade.case.item", string="Purchase item", required=True,
        ondelete="restrict", index=True,
        help="BR-121: the uniqueness key MUST include the purchase item id.")
    goods_description = fields.Char(string="Goods description")
    shortfall_tonnage = fields.Float(string="Shortfall tonnage", required=True)
    shortfall_amount_base = fields.Float(string="Shortfall amount (IRR)")
    state = fields.Selection(SHORTFALL_STATES, string="State", required=True,
                             default="open", tracking=True)
    notes = fields.Text(string="Notes")

    # BR-121: a real DB unique key that INCLUDES the item id.
    # [FIX-1] Odoo 19 no longer supports `_sql_constraints`; models.Constraint
    # is the official replacement (the old attribute was silently ignored and
    # the unique index was never created).
    _shortfall_item_uniq = models.Constraint(
        "unique(trade_case_id, trade_case_item_id)",
        "A shortfall row already exists for this purchase item (BR-121).",
    )

    @api.constrains("shortfall_tonnage")
    def _check_tonnage(self):
        for record in self:
            if record.shortfall_tonnage <= 0:
                raise ValidationError(_("The shortfall tonnage must be greater than zero."))

    @api.constrains("trade_case_item_id", "trade_case_id")
    def _check_item_belongs_to_case(self):
        for record in self:
            if record.trade_case_item_id.case_id != record.trade_case_id:
                raise ValidationError(
                    _("The purchase item must belong to the same trade case."))
PYEOF

# --------------------------------------------- security (فایل جدید مستقل) --
write_utf8 "${MOD_DIR}/security/itr_core_phase4_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <!-- Phase-4 skeleton record rules (SEC-012/SEC-013 basis).
             The fine grained "mine / my team / all" matrix is completed in
             phase 7 - deliberately NOT invented twice here. -->
        <record id="rule_itr_trade_case_company" model="ir.rule">
            <field name="name">Trade case: company rule</field>
            <field name="model_id" ref="itr_core.model_itr_trade_case"/>
            <field name="domain_force">[('company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>

        <record id="rule_itr_trade_case_item_company" model="ir.rule">
            <field name="name">Trade case item: company rule</field>
            <field name="model_id" ref="itr_core.model_itr_trade_case_item"/>
            <field name="domain_force">[('case_id.company_id', 'in', company_ids)]</field>
            <field name="groups" eval="[(4, ref('base.group_user'))]"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------- data --
write_utf8 "${MOD_DIR}/data/itr_trade_case_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <!-- 4.1: automatic sequence of the trade case -->
        <record id="seq_itr_trade_case" model="ir.sequence">
            <field name="name">Trade Case</field>
            <field name="code">itr.trade.case</field>
            <field name="prefix">TC/%(range_year)s/</field>
            <field name="padding">4</field>
            <field name="company_id" eval="False"/>
        </record>

        <!-- C1: the assignment deadline is a PARAMETER, never hard coded (Q07) -->
        <record id="param_default_assignment_days" model="ir.config_parameter">
            <field name="key">itr_core.default_assignment_days</field>
            <field name="value">2</field>
        </record>
    </data>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/data/itr_core_notify_events.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Phase 4 seeds ONLY the events its own checklist mandates (4.6/4.7).
         The full business catalogue (SRS 11-3) is wired in phase 10; phase 10
         MUST update/refer to these xmlids instead of re-creating the same
         event_key with another xmlid (the event_key has a real unique index). -->
    <data noupdate="1">

        <!-- ★ 4.7 / UAT-07: the most critical event of the project -->
        <record id="event_trade_case_back_to_finance_supervisor" model="itr.notification.event">
            <field name="event_key">trade_case.back_to_finance_supervisor</field>
            <field name="title">Trade case review result back to the CEO / finance supervisor desk</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="True"/>
            <field name="send_sms" eval="True"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Trade case {{name}} passed the specialist reviews</field>
            <field name="internal_body">Trade case {{name}} passed legal, treasury and receivables and is one step before the finance supervisor desk (signature stage).</field>
            <field name="sms_body">پرونده {{name}} تاییدات تخصصی را گذراند و آماده امضای فیزیکی است.</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <!-- mandatory legacy alias (UAT-07) -->
        <record id="alias_case_result_to_ceo" model="itr.notification.alias">
            <field name="alias_key">case.result_to_ceo</field>
            <field name="event_id" ref="itr_core.event_trade_case_back_to_finance_supervisor"/>
            <field name="note">Legacy name used by older documents; kept forever (checklist 10.2).</field>
        </record>

        <!-- 4.6 / G02: immediate rejection SMS to the CEO -->
        <record id="event_deal_rejected" model="itr.notification.event">
            <field name="event_key">deal.rejected</field>
            <field name="title">Deal rejected (terminal)</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="True"/>
            <field name="send_sms" eval="True"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="internal_subject">Trade case {{name}} was rejected</field>
            <field name="internal_body">Trade case {{name}} was rejected and closed. Reason: {{reason}}</field>
            <field name="sms_body">پرونده {{name}} رد و مختومه شد. علت: {{reason}}</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <!-- pattern B parking (SRS 11-3 group A, needed by action_submit) -->
        <record id="event_case_parked_waiting_supply" model="itr.notification.event">
            <field name="event_key">case.parked_waiting_supply</field>
            <field name="title">Trade case parked - waiting for supply</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">30</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Trade case {{name}} is waiting for supply</field>
            <field name="internal_body">Pattern B: trade case {{name}} is parked until the goods and the final purchase rate are secured (BR-004: no sales slip exists yet).</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <!-- three station-level rejection events (SRS 11-3, used in 4.6) -->
        <record id="event_case_legal_rejected" model="itr.notification.event">
            <field name="event_key">case.legal_rejected</field>
            <field name="title">Trade case rejected by legal</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="True"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Legal rejection of {{name}}</field>
            <field name="internal_body">The legal station rejected trade case {{name}}. Reason: {{reason}}</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <record id="event_case_treasury_rejected" model="itr.notification.event">
            <field name="event_key">case.treasury_rejected</field>
            <field name="title">Trade case rejected by treasury</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="True"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Treasury rejection of {{name}}</field>
            <field name="internal_body">The treasury station rejected trade case {{name}}. Reason: {{reason}}</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <record id="event_case_receivables_rejected" model="itr.notification.event">
            <field name="event_key">case.receivables_rejected</field>
            <field name="title">Trade case rejected by receivables</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="True"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_supervisor'))]"/>
            <field name="internal_subject">Receivables rejection of {{name}}</field>
            <field name="internal_body">The receivables station rejected trade case {{name}}. Reason: {{reason}}</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

        <!-- signature completed (used by action_confirm_signed) -->
        <record id="event_case_signed_and_uploaded" model="itr.notification.event">
            <field name="event_key">case.signed_and_uploaded</field>
            <field name="title">Trade case physically signed and uploaded</field>
            <field name="category">workflow</field>
            <field name="is_active" eval="True"/>
            <field name="is_critical" eval="False"/>
            <field name="send_sms" eval="False"/>
            <field name="cooldown_minutes">5</field>
            <field name="dynamic_user_field">requested_by</field>
            <field name="recipient_group_ids" eval="[(4, ref('itr_core.group_finance_user'))]"/>
            <field name="internal_subject">Trade case {{name}} signed</field>
            <field name="internal_body">The signed scan of trade case {{name}} was uploaded; sales slips may now be issued (G03).</field>
            <field name="is_seed" eval="True"/>
            <field name="allow_seed_overwrite" eval="True"/>
        </record>

    </data>
</odoo>
XMLEOF

# ------------------------------------------------------------------ views --
write_utf8 "${MOD_DIR}/views/itr_trade_case_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- 4.1: form with FOUR tabs + chatter -->
    <record id="view_itr_trade_case_form" model="ir.ui.view">
        <field name="name">itr.trade.case.form</field>
        <field name="model">itr.trade.case</field>
        <field name="arch" type="xml">
            <form string="Trade Case">
                <header>
                    <button name="action_submit" type="object" string="Submit"
                            class="btn-primary" invisible="state != 'draft'"/>
                    <button name="action_supply_ready" type="object" string="Supply secured"
                            class="btn-primary" invisible="state != 'waiting_supply'"
                            groups="itr_core.group_finance_user,itr_core.group_finance_supervisor,itr_core.group_ceo"/>
                    <button name="action_legal_approve" type="object" string="Legal: approve"
                            class="btn-primary" invisible="state != 'legal_review'"
                            groups="itr_core.group_legal_reviewer"/>
                    <button name="action_legal_return" type="object" string="Legal: documents incomplete"
                            invisible="state != 'legal_review'" groups="itr_core.group_legal_reviewer"
                            context="{'itr_reason': 'Documents incomplete'}"/>
                    <button name="action_legal_reject" type="object" string="Legal: reject deal"
                            invisible="state != 'legal_review'" groups="itr_core.group_legal_reviewer"
                            context="{'itr_reason': 'Rejected by legal'}"/>
                    <button name="action_treasury_approve" type="object" string="Treasury: approve"
                            class="btn-primary" invisible="state != 'treasury_review'"
                            groups="itr_core.group_treasury_user"/>
                    <button name="action_treasury_return" type="object" string="Treasury: documents incomplete"
                            invisible="state != 'treasury_review'" groups="itr_core.group_treasury_user"
                            context="{'itr_reason': 'Documents incomplete'}"/>
                    <button name="action_treasury_reject" type="object" string="Treasury: reject deal"
                            invisible="state != 'treasury_review'" groups="itr_core.group_treasury_user"
                            context="{'itr_reason': 'Rejected by treasury'}"/>
                    <button name="action_receivables_approve" type="object" string="Receivables: approve"
                            class="btn-primary" invisible="state != 'receivables_review'"
                            groups="itr_core.group_receivables_user"/>
                    <button name="action_receivables_return" type="object" string="Receivables: documents incomplete"
                            invisible="state != 'receivables_review'" groups="itr_core.group_receivables_user"
                            context="{'itr_reason': 'Documents incomplete'}"/>
                    <button name="action_receivables_reject" type="object" string="Receivables: reject deal"
                            invisible="state != 'receivables_review'" groups="itr_core.group_receivables_user"
                            context="{'itr_reason': 'Rejected by receivables'}"/>
                    <button name="action_resubmit" type="object" string="Resubmit after completion"
                            class="btn-primary" invisible="state != 'returned'"
                            groups="itr_core.group_finance_user,itr_core.group_finance_supervisor"/>
                    <button name="action_confirm_signed" type="object" string="Confirm physical signature"
                            class="btn-primary" invisible="state != 'pending_signature'"
                            groups="itr_core.group_finance_supervisor,itr_core.group_document_signer"/>
                    <field name="state" widget="statusbar"
                           statusbar_visible="draft,legal_review,treasury_review,receivables_review,pending_signature,approved"/>
                </header>
                <sheet>
                    <div class="oe_title">
                        <h1><field name="name" readonly="1"/></h1>
                    </div>
                    <notebook>
                        <!-- Tab 1/4: main information -->
                        <page string="Main information" name="main">
                            <group>
                                <group>
                                    <field name="requested_by" readonly="state != 'draft'"/>
                                    <field name="deal_pattern" readonly="state != 'draft'"/>
                                    <field name="company_id" groups="base.group_multi_company"/>
                                    <field name="factory_id"/>
                                    <field name="buyer_id" invisible="deal_pattern != 'sell_first'"/>
                                </group>
                                <group>
                                    <field name="border_id"/>
                                    <field name="destination"/>
                                    <field name="current_owner_id" readonly="1"/>
                                    <field name="owner_deadline" readonly="1"/>
                                    <field name="review_round" readonly="1"/>
                                </group>
                            </group>
                            <group string="Financial roll-up (read-only, single money engine)">
                                <group>
                                    <field name="total_contract_tonnage" readonly="1"/>
                                    <field name="purchase_total_base" readonly="1"/>
                                </group>
                                <group>
                                    <field name="sales_total_base" readonly="1"/>
                                    <field name="estimated_profit_base" readonly="1"/>
                                </group>
                            </group>
                        </page>
                        <!-- Tab 2/4: multi-goods items -->
                        <page string="Goods items" name="items">
                            <field name="item_ids" readonly="state in ('rejected', 'closed')">
                                <list editable="bottom">
                                    <field name="sequence" widget="handle"/>
                                    <field name="name"/>
                                    <field name="row_kind"/>
                                    <field name="thickness_mm"/>
                                    <field name="width_cm"/>
                                    <field name="contract_tonnage"/>
                                    <field name="reserved_tonnage" readonly="1"/>
                                    <field name="effective_tonnage" readonly="1"/>
                                    <field name="remaining_tonnage" readonly="1"/>
                                    <field name="purchase_price_unit"/>
                                    <field name="purchase_currency_id"/>
                                    <field name="purchase_base_amount" readonly="1"/>
                                    <field name="sale_price_unit"/>
                                    <field name="sale_currency_id"/>
                                    <field name="sale_base_amount" readonly="1"/>
                                    <field name="rate_locked" readonly="1"/>
                                </list>
                            </field>
                            <group string="Proforma anchors (operational, never a sales slip)">
                                <field name="proforma_purchase_ref"/>
                                <field name="proforma_sales_ref"/>
                            </group>
                        </page>
                        <!-- Tab 3/4: reviews and assignment history -->
                        <page string="Reviews and history" name="reviews">
                            <group string="Three-station specialist chain">
                                <group>
                                    <field name="legal_result" readonly="1"/>
                                    <field name="legal_by_id" readonly="1"/>
                                    <field name="legal_on" readonly="1"/>
                                    <field name="treasury_result" readonly="1"/>
                                    <field name="treasury_by_id" readonly="1"/>
                                    <field name="treasury_on" readonly="1"/>
                                </group>
                                <group>
                                    <field name="receivables_result" readonly="1"/>
                                    <field name="receivables_by_id" readonly="1"/>
                                    <field name="receivables_on" readonly="1"/>
                                    <field name="last_return_reason" readonly="1"/>
                                    <field name="rejection_reason" readonly="1"/>
                                </group>
                            </group>
                            <group string="Assignment history (append-only)">
                                <field name="assignment_log_ids" nolabel="1" readonly="1">
                                    <list>
                                        <field name="assigned_on"/>
                                        <field name="from_user_id"/>
                                        <field name="to_user_id"/>
                                        <field name="assigned_by_id"/>
                                        <field name="state_at_assignment"/>
                                        <field name="reason"/>
                                    </list>
                                </field>
                            </group>
                        </page>
                        <!-- Tab 4/4: signature and documents (4.8) -->
                        <page string="Signature and documents" name="signature">
                            <group>
                                <group>
                                    <field name="signed_document" filename="signed_document_filename"
                                           readonly="state not in ('pending_signature',)"/>
                                    <field name="signed_document_filename" invisible="1"/>
                                </group>
                                <group>
                                    <field name="signed_by_id" readonly="1"/>
                                    <field name="signed_on" readonly="1"/>
                                </group>
                            </group>
                        </page>
                    </notebook>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="view_itr_trade_case_list" model="ir.ui.view">
        <field name="name">itr.trade.case.list</field>
        <field name="model">itr.trade.case</field>
        <field name="arch" type="xml">
            <list string="Trade Cases">
                <field name="name"/>
                <field name="requested_by"/>
                <field name="deal_pattern"/>
                <field name="factory_id"/>
                <field name="total_contract_tonnage"/>
                <field name="estimated_profit_base"/>
                <field name="current_owner_id"/>
                <field name="state"
                       decoration-info="state in ('draft','waiting_supply')"
                       decoration-warning="state in ('legal_review','treasury_review','receivables_review','pending_signature','returned')"
                       decoration-success="state in ('approved','slips_issued','closed')"
                       decoration-danger="state == 'rejected'"
                       widget="badge"/>
            </list>
        </field>
    </record>

    <!-- 4.11: state kanban with colours (display only - UX-063: no drag
         transition, the state can only move through server actions) -->
    <record id="view_itr_trade_case_kanban" model="ir.ui.view">
        <field name="name">itr.trade.case.kanban</field>
        <field name="model">itr.trade.case</field>
        <field name="arch" type="xml">
            <kanban default_group_by="state" records_draggable="false" group_create="false">
                <field name="name"/>
                <field name="state"/>
                <field name="requested_by"/>
                <field name="current_owner_id"/>
                <field name="total_contract_tonnage"/>
                <templates>
                    <t t-name="card">
                        <div class="oe_kanban_card oe_kanban_global_click">
                            <strong><field name="name"/></strong>
                            <div><field name="requested_by"/></div>
                            <div>
                                <span class="badge text-bg-info"
                                      t-if="record.state.raw_value in ('draft','waiting_supply')">
                                    <field name="state"/>
                                </span>
                                <span class="badge text-bg-warning"
                                      t-if="record.state.raw_value in ('legal_review','treasury_review','receivables_review','pending_signature','returned')">
                                    <field name="state"/>
                                </span>
                                <span class="badge text-bg-success"
                                      t-if="record.state.raw_value in ('approved','slips_issued','closed')">
                                    <field name="state"/>
                                </span>
                                <span class="badge text-bg-danger"
                                      t-if="record.state.raw_value == 'rejected'">
                                    <field name="state"/>
                                </span>
                            </div>
                            <div>Owner: <field name="current_owner_id"/></div>
                            <div>Tonnage: <field name="total_contract_tonnage"/></div>
                        </div>
                    </t>
                </templates>
            </kanban>
        </field>
    </record>

    <record id="view_itr_trade_case_search" model="ir.ui.view">
        <field name="name">itr.trade.case.search</field>
        <field name="model">itr.trade.case</field>
        <field name="arch" type="xml">
            <search string="Trade Cases">
                <field name="name"/>
                <field name="requested_by"/>
                <field name="factory_id"/>
                <field name="current_owner_id"/>
                <filter name="my_cases" string="My cases"
                        domain="[('current_owner_id', '=', uid)]"/>
                <filter name="open_cases" string="Open"
                        domain="[('state', 'not in', ('closed', 'rejected'))]"/>
                <filter name="group_state" string="State" context="{'group_by': 'state'}"/>
                <filter name="group_owner" string="Owner" context="{'group_by': 'current_owner_id'}"/>
            </search>
        </field>
    </record>

    <record id="action_itr_trade_case" model="ir.actions.act_window">
        <field name="name">Trade Cases</field>
        <field name="res_model">itr.trade.case</field>
        <field name="view_mode">kanban,list,form</field>
        <field name="context">{'search_default_open_cases': 1}</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_factory_shortfall_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_factory_shortfall_list" model="ir.ui.view">
        <field name="name">itr.factory.shortfall.list</field>
        <field name="model">itr.factory.shortfall</field>
        <field name="arch" type="xml">
            <list string="Factory Shortfall Ledger">
                <field name="create_date"/>
                <field name="supplier_id"/>
                <field name="trade_case_id"/>
                <field name="trade_case_item_id"/>
                <field name="shortfall_tonnage"/>
                <field name="shortfall_amount_base"/>
                <field name="state" widget="badge"
                       decoration-danger="state == 'open'"
                       decoration-warning="state == 'partially_settled'"
                       decoration-success="state == 'settled'"/>
            </list>
        </field>
    </record>

    <record id="view_itr_factory_shortfall_form" model="ir.ui.view">
        <field name="name">itr.factory.shortfall.form</field>
        <field name="model">itr.factory.shortfall</field>
        <field name="arch" type="xml">
            <form string="Factory Shortfall">
                <sheet>
                    <group>
                        <group>
                            <field name="supplier_id"/>
                            <field name="trade_case_id"/>
                            <field name="trade_case_item_id"
                                   domain="[('case_id', '=', trade_case_id)]"/>
                            <field name="goods_description"/>
                        </group>
                        <group>
                            <field name="shortfall_tonnage"/>
                            <field name="shortfall_amount_base"/>
                            <field name="state"/>
                        </group>
                    </group>
                    <field name="notes" placeholder="Notes..."/>
                </sheet>
                <chatter/>
            </form>
        </field>
    </record>

    <record id="action_itr_factory_shortfall" model="ir.actions.act_window">
        <field name="name">Factory Shortfall Ledger</field>
        <field name="res_model">itr.factory.shortfall</field>
        <field name="view_mode">list,form</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_case_assignment_views.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <record id="view_itr_case_assignment_log_list" model="ir.ui.view">
        <field name="name">itr.case.assignment.log.list</field>
        <field name="model">itr.case.assignment.log</field>
        <field name="arch" type="xml">
            <list string="Assignment Log" create="false" edit="false" delete="false">
                <field name="assigned_on"/>
                <field name="case_id"/>
                <field name="from_user_id"/>
                <field name="to_user_id"/>
                <field name="assigned_by_id"/>
                <field name="state_at_assignment"/>
                <field name="reason"/>
            </list>
        </field>
    </record>

    <record id="action_itr_case_assignment_log" model="ir.actions.act_window">
        <field name="name">Assignment Log</field>
        <field name="res_model">itr.case.assignment.log</field>
        <field name="view_mode">list</field>
    </record>
</odoo>
XMLEOF

write_utf8 "${MOD_DIR}/views/itr_core_phase4_menus.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- hangs under the phase-3 root menu (reuse, not a new root) -->
    <menuitem id="menu_itr_trade_root"
              name="Trade Operations"
              parent="itr_core.menu_itr_core_root"
              sequence="10"/>

    <menuitem id="menu_itr_trade_case"
              name="Trade Cases"
              parent="menu_itr_trade_root"
              action="action_itr_trade_case"
              sequence="10"/>

    <menuitem id="menu_itr_factory_shortfall"
              name="Factory Shortfall Ledger"
              parent="menu_itr_trade_root"
              action="action_itr_factory_shortfall"
              sequence="20"
              groups="itr_core.group_finance_supervisor,itr_core.group_financial_manager,itr_core.group_ceo,itr_core.group_auditor"/>

    <menuitem id="menu_itr_case_assignment_log"
              name="Assignment Log"
              parent="menu_itr_trade_root"
              action="action_itr_case_assignment_log"
              sequence="30"/>
</odoo>
XMLEOF

# ------------------------------------------------------------------ tests --
write_utf8 "${MOD_DIR}/tests/test_trade_case_phase4.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 4 automated tests (Q04/G01: real seeded users, never Administrator).

Positive: pattern A end-to-end up to the signature; pattern B parks in
waiting_supply and continues after supply. Negative: non-CEO requested_by
(UI domain AND raw write), rejection is terminal + SMS event, signature
guard, direct state write via RPC, out-of-team reassignment.
"""
import base64

from odoo.exceptions import UserError, ValidationError
from odoo.tests import tagged

from .common import ItrCoreCase


@tagged("post_install", "-at_install", "itr_core")
class TestItrTradeCasePhase4(ItrCoreCase):

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
        # make notify() deliver synchronously inside the test transaction
        cls.Case = cls.env["itr.trade.case"].with_context(itr_notify_sync=True)

    # ------------------------------------------------------------- helpers
    def _new_case(self, pattern="buy_first", sale_rate=110.0, purchase_rate=100.0):
        return self.Case.with_user(self.fin_user).create({
            "requested_by": self.ceo.id,
            "deal_pattern": pattern,
            "item_ids": [(0, 0, {
                "name": "TEST steel coil 2mm",
                "row_kind": "both",
                "thickness_mm": 2.0,
                "contract_tonnage": 100.0,
                "purchase_price_unit": purchase_rate,
                "sale_price_unit": sale_rate,
            })],
        })

    def _dispatch_rows(self, event_key, case):
        return self.env["itr.notification.dispatch.log"].sudo().search([
            ("event_key", "=", event_key),
            ("res_model", "=", "itr.trade.case"),
            ("res_id", "=", case.id),
        ])

    def _run_chain_to_signature(self, case):
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_approve()
        case.with_user(self.treasury).action_treasury_approve()
        case.with_user(self.receivables).action_receivables_approve()
        return case

    # ------------------------------------------------------------ positive
    def test_10_pattern_a_full_flow_to_signature(self):
        case = self._new_case()
        self.assertTrue(case.name.startswith("TC/"), "4.1: automatic sequence")
        self._run_chain_to_signature(case)
        self.assertEqual(case.state, "pending_signature")
        # 4.7: the critical event fired exactly before the supervisor desk
        rows = self._dispatch_rows("trade_case.back_to_finance_supervisor", case)
        self.assertTrue(rows, "UAT-07: the critical event must be in the dispatch log")
        self.assertIn(self.ceo.id, rows.mapped("recipient_user_id").ids,
                      "requested_by must be a recipient")
        # 4.8: exit without the signed scan is blocked
        with self.assertRaises(UserError):
            case.with_user(self.fin_sup).action_confirm_signed()
        case.with_context(itr_trade_state_engine=True).write({
            "signed_document": base64.b64encode(b"TEST signed scan"),
            "signed_document_filename": "signed.pdf",
        })
        case.with_user(self.fin_sup).action_confirm_signed()
        self.assertEqual(case.state, "approved")
        self.assertTrue(all(case.item_ids.mapped("rate_locked")), "FIN-014 lock on signature")
        # 4.9: the roll-up equals the single money engine, always
        totals = self.env["itr.money.engine"].case_totals(case)
        self.assertAlmostEqual(case.estimated_profit_base, totals["estimated_profit"])

    def test_11_pattern_b_parks_then_continues(self):
        case = self._new_case(pattern="sell_first", purchase_rate=0.0)
        case.with_user(self.fin_user).action_submit()
        self.assertEqual(case.state, "waiting_supply")
        # BR-004: no sales slip model may exist before phase 5
        self.assertNotIn("itr.sales.slip", self.env,
                         "4.4/BR-004: itr.sales.slip must not exist in phase 4")
        # release refused while the purchase rate is not final
        with self.assertRaises(UserError):
            case.with_user(self.fin_user).action_supply_ready()
        case.item_ids.write({"purchase_price_unit": 95.0})
        case.with_user(self.fin_user).action_supply_ready()
        self.assertEqual(case.state, "legal_review")

    def test_12_deficiency_returns_to_finance_and_resubmits(self):
        case = self._new_case()
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_return(reason="TEST missing contract scan")
        self.assertEqual(case.state, "returned")
        self.assertIn("TEST missing contract scan", case.last_return_reason)
        case.with_user(self.fin_user).action_resubmit()
        self.assertEqual(case.state, "legal_review")
        self.assertEqual(case.review_round, 2)

    def test_13_alias_resolves_to_official_event(self):
        """UAT-07: the legacy name reaches the official event."""
        alias = self.env["itr.notification.alias"].search(
            [("alias_key", "=", "case.result_to_ceo")], limit=1)
        self.assertTrue(alias, "mandatory alias case.result_to_ceo missing")
        self.assertEqual(alias.event_id.event_key, "trade_case.back_to_finance_supervisor")

    def test_14_assignment_creates_activity_and_log(self):
        case = self._new_case()
        case.with_user(self.fin_user).action_submit()
        before = len(case.assignment_log_ids)
        case.with_user(self.fin_sup).assign_to(self.fin_user, reason="TEST workload balance")
        self.assertEqual(len(case.assignment_log_ids), before + 1)
        self.assertEqual(case.current_owner_id, self.fin_user)
        activities = self.env["mail.activity"].sudo().search([
            ("res_model", "=", "itr.trade.case"),
            ("res_id", "=", case.id),
            ("user_id", "=", self.fin_user.id),
        ])
        self.assertTrue(activities, "UX-004: assignment must schedule a mail.activity")

    # ------------------------------------------------------------ negative
    def test_20_requested_by_non_ceo_refused_ui_and_rpc(self):
        # (create path)
        with self.assertRaises(ValidationError):
            self.Case.with_user(self.fin_user).create({
                "requested_by": self.fin_user.id,
                "item_ids": [(0, 0, {"name": "TEST", "contract_tonnage": 1.0})],
            })
        # (raw RPC write path on a valid case)
        case = self._new_case()
        with self.assertRaises(UserError):
            case.with_user(self.fin_user).write({"requested_by": self.fin_user.id})

    def test_21_direct_state_write_is_refused(self):
        case = self._new_case()
        with self.assertRaises(UserError):
            case.with_user(self.fin_user).write({"state": "approved"})
        with self.assertRaises(UserError):
            case.sudo().write({"state": "approved"})

    def test_22_rejection_is_terminal_and_notifies_ceo(self):
        case = self._new_case()
        case.with_user(self.fin_user).action_submit()
        case.with_user(self.legal).action_legal_reject(reason="TEST sanctions risk")
        self.assertEqual(case.state, "rejected")
        rows = self._dispatch_rows("deal.rejected", case)
        self.assertTrue(rows, "G02: deal.rejected must be dispatched immediately")
        self.assertFalse(case.current_owner_id,
                         "G02: a rejected case sits on nobody's desk")
        # G02: it NEVER returns to the finance specialist
        with self.assertRaises(UserError):
            case.with_user(self.fin_user).action_resubmit()
        with self.assertRaises(UserError):
            case._do_transition("legal_review")

    def test_23_wrong_role_is_refused_on_server(self):
        case = self._new_case()
        case.with_user(self.fin_user).action_submit()
        # a transport user must not approve the legal station (RPC-level guard)
        with self.assertRaises(UserError):
            case.with_user(self.transport_docs).action_legal_approve()
        # the treasury cannot act while the case sits at the legal station
        with self.assertRaises(UserError):
            case.with_user(self.treasury).action_treasury_approve()

    def test_24_signature_stage_entry_free_exit_guarded(self):
        case = self._new_case()
        self._run_chain_to_signature(case)
        self.assertEqual(case.state, "pending_signature", "entry must be free")
        with self.assertRaises(UserError):
            case.with_user(self.fin_sup).action_confirm_signed()
        # wrong role with a document is refused too
        case.with_context(itr_trade_state_engine=True).write({
            "signed_document": base64.b64encode(b"TEST"),
        })
        with self.assertRaises(UserError):
            case.with_user(self.transport_docs).action_confirm_signed()

    def test_25_out_of_team_reassignment_refused(self):
        case = self._new_case()
        case.with_user(self.fin_user).action_submit()
        # the finance supervisor's team does not contain the customs officer
        with self.assertRaises(UserError):
            case.with_user(self.fin_sup).assign_to(
                self.transport_docs, reason="TEST out of team")
        # but the CEO may assign freely
        case.with_user(self.ceo).assign_to(self.transport_docs, reason="TEST ceo override")
        self.assertEqual(case.current_owner_id, self.transport_docs)

    def test_26_shortfall_unique_key_includes_item(self):
        """BR-121 skeleton check."""
        case = self._new_case()
        factory = self.env["res.partner"].create({
            "name": "TEST factory", "is_factory": True, "is_company": True})
        vals = {
            "supplier_id": factory.id,
            "trade_case_id": case.id,
            "trade_case_item_id": case.item_ids[0].id,
            "shortfall_tonnage": 4.0,
        }
        self.env["itr.factory.shortfall"].create(vals)
        with self.assertRaises(Exception):
            with self.env.cr.savepoint():
                self.env["itr.factory.shortfall"].create(vals)
PYEOF

# =============================================================================
step "4) پچ افزایشی و idempotent چهار فایل مشترک فاز ۳ (C2 — بدون بازنویسی)"
# =============================================================================
python3 - "${MOD_DIR}" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Incremental, idempotent patch of the shared phase-3 files (concern C2).

Never rewrites a phase-3 file: it only INSERTS what is missing. Running it
twice changes nothing (NFR-002). Any unexpected file shape aborts loudly so
the phase stops instead of silently corrupting phase 3 (annex C).
"""
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


# ---- models/__init__.py -----------------------------------------------------
# [FIX-2] itr_trade_case MUST be imported before itr_trade_case_item so the
# comodel 'itr.trade.case' exists in the registry when case_id is set up.
path = os.path.join(mod_dir, "models", "__init__.py")
text = read(path)
phase4_imports = (
    "from . import money_engine",
    "from . import itr_trade_case",
    "from . import itr_trade_case_item",
    "from . import itr_case_assignment_log",
    "from . import itr_factory_shortfall",
)
existing_lines = text.splitlines()
if any(line.strip() in phase4_imports for line in existing_lines):
    # a previous run already inserted (possibly mis-ordered) phase-4 imports:
    # keep every phase-3 line untouched and re-append the phase-4 block in
    # the correct order (idempotent - identical result on every run).
    kept = [line for line in existing_lines if line.strip() not in phase4_imports]
    base = "\n".join(kept).rstrip("\n")
    new_text = base + ("\n" if base else "") + "\n".join(phase4_imports) + "\n"
    if new_text != text:
        text = new_text
        changed.append("models/__init__.py phase-4 imports re-ordered (trade_case before item)")
else:
    for imp in phase4_imports:
        text = text.rstrip("\n") + "\n" + imp + "\n"
        changed.append("models/__init__.py + %s" % imp)
write(path, text)

# ---- tests/__init__.py ------------------------------------------------------
path = os.path.join(mod_dir, "tests", "__init__.py")
text = read(path)
imp = "from . import test_trade_case_phase4"
if imp not in text:
    text = text.rstrip("\n") + "\n" + imp + "\n"
    changed.append("tests/__init__.py + %s" % imp)
write(path, text)

# ---- __manifest__.py --------------------------------------------------------
path = os.path.join(mod_dir, "__manifest__.py")
text = read(path)
anchor = '"views/itr_core_menus.xml",'
if anchor not in text:
    print("FATAL: manifest anchor not found - phase 3 contract changed", file=sys.stderr)
    sys.exit(2)
before_anchor = [
    '"security/itr_core_phase4_rules.xml",',
    '"data/itr_trade_case_data.xml",',
    '"data/itr_core_notify_events.xml",',
    '"views/itr_trade_case_views.xml",',
    '"views/itr_factory_shortfall_views.xml",',
    '"views/itr_case_assignment_views.xml",',
]
after_anchor = ['"views/itr_core_phase4_menus.xml",']
indent = "        "
for entry in before_anchor:
    if entry not in text:
        text = text.replace(indent + anchor, indent + entry + "\n" + indent + anchor)
        changed.append("manifest + %s" % entry)
for entry in after_anchor:
    if entry not in text:
        text = text.replace(indent + anchor, indent + anchor + "\n" + indent + entry)
        changed.append("manifest + %s" % entry)
# dependencies: product (Q13 - reuse the standard catalogue, no parallel model)
if '"product"' not in text:
    dep_anchor = '"depends": ["base", "mail", "itr_base", "itr_notify"],'
    if dep_anchor not in text:
        print("FATAL: depends anchor not found - phase 3 contract changed", file=sys.stderr)
        sys.exit(2)
    text = text.replace(
        dep_anchor,
        '"depends": ["base", "mail", "product", "itr_base", "itr_notify"],')
    changed.append("manifest + depends product")
# version bump (idempotent)
if '"version": "19.0.1.0.0",' in text:
    text = text.replace('"version": "19.0.1.0.0",', '"version": "19.0.1.1.0",')
    changed.append("manifest version -> 19.0.1.1.0")
write(path, text)
# post-condition: every phase-4 data file must now be referenced (never silent)
for entry in before_anchor + after_anchor:
    if entry not in text:
        print("FATAL: manifest patch failed for %s" % entry, file=sys.stderr)
        sys.exit(2)

# ---- security/ir.model.access.csv -------------------------------------------
path = os.path.join(mod_dir, "security", "ir.model.access.csv")
text = read(path)
acl_lines = [
    # itr.trade.case — SEC-011: read for every internal user; write for the
    # roles that really act on it (station users need write for their audit
    # fields; every transition is still role-guarded again in the methods).
    "access_itr_trade_case_user,itr.trade.case user read,model_itr_trade_case,base.group_user,1,0,0,0",
    "access_itr_trade_case_fin_user,itr.trade.case fin user,model_itr_trade_case,itr_core.group_finance_user,1,1,1,1",
    "access_itr_trade_case_fin_sup,itr.trade.case fin sup,model_itr_trade_case,itr_core.group_finance_supervisor,1,1,1,0",
    "access_itr_trade_case_fin_mgr,itr.trade.case fin mgr,model_itr_trade_case,itr_core.group_financial_manager,1,1,1,0",
    "access_itr_trade_case_ceo,itr.trade.case ceo,model_itr_trade_case,itr_core.group_ceo,1,1,1,0",
    "access_itr_trade_case_legal,itr.trade.case legal,model_itr_trade_case,itr_core.group_legal_reviewer,1,1,0,0",
    "access_itr_trade_case_treasury,itr.trade.case treasury,model_itr_trade_case,itr_core.group_treasury_user,1,1,0,0",
    "access_itr_trade_case_receivables,itr.trade.case receivables,model_itr_trade_case,itr_core.group_receivables_user,1,1,0,0",
    "access_itr_trade_case_signer,itr.trade.case signer,model_itr_trade_case,itr_core.group_document_signer,1,1,0,0",
    "access_itr_trade_case_auditor,itr.trade.case auditor,model_itr_trade_case,itr_core.group_auditor,1,0,0,0",
    # itr.trade.case.item
    "access_itr_trade_case_item_user,itr.trade.case.item user read,model_itr_trade_case_item,base.group_user,1,0,0,0",
    "access_itr_trade_case_item_fin_user,itr.trade.case.item fin user,model_itr_trade_case_item,itr_core.group_finance_user,1,1,1,1",
    "access_itr_trade_case_item_fin_sup,itr.trade.case.item fin sup,model_itr_trade_case_item,itr_core.group_finance_supervisor,1,1,1,1",
    "access_itr_trade_case_item_ceo,itr.trade.case.item ceo,model_itr_trade_case_item,itr_core.group_ceo,1,1,1,0",
    # itr.factory.shortfall (skeleton)
    "access_itr_factory_shortfall_user,itr.factory.shortfall user read,model_itr_factory_shortfall,base.group_user,1,0,0,0",
    "access_itr_factory_shortfall_fin_user,itr.factory.shortfall fin user,model_itr_factory_shortfall,itr_core.group_finance_user,1,1,1,0",
    "access_itr_factory_shortfall_fin_sup,itr.factory.shortfall fin sup,model_itr_factory_shortfall,itr_core.group_finance_supervisor,1,1,1,0",
    "access_itr_factory_shortfall_ceo,itr.factory.shortfall ceo,model_itr_factory_shortfall,itr_core.group_ceo,1,1,1,0",
    # itr.case.assignment.log (append-only: model itself blocks write/unlink)
    "access_itr_case_assignment_log_user,itr.case.assignment.log user,model_itr_case_assignment_log,base.group_user,1,0,1,0",
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
MARK = "#### itr_core phase-4 translations ####"
if MARK not in text:
    text = text.rstrip("\n") + "\n\n" + MARK + """

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_trade_case
msgid "Trade Case"
msgstr "پروندهٔ بازرگانی"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_trade_case_item
msgid "Trade Case Item"
msgstr "ردیف کالای پرونده"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_factory_shortfall
msgid "Factory Shortfall Ledger"
msgstr "دفتر طلب از کارخانه"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_case_assignment_log
msgid "Trade Case Assignment Log"
msgstr "تاریخچهٔ ارجاع پرونده"

#. module: itr_core
#: model:ir.model,name:itr_core.model_itr_money_engine
msgid "Iran Trade Money Engine"
msgstr "موتور مالی واحد بازرگانی"

#. module: itr_core
#: model:ir.ui.menu,name:itr_core.menu_itr_trade_root
msgid "Trade Operations"
msgstr "عملیات بازرگانی"

#. module: itr_core
#: model:ir.actions.act_window,name:itr_core.action_itr_trade_case
#: model:ir.ui.menu,name:itr_core.menu_itr_trade_case
msgid "Trade Cases"
msgstr "پرونده‌های بازرگانی"

#. module: itr_core
#: model:ir.actions.act_window,name:itr_core.action_itr_factory_shortfall
#: model:ir.ui.menu,name:itr_core.menu_itr_factory_shortfall
msgid "Factory Shortfall Ledger"
msgstr "دفتر طلب از کارخانه"

#. module: itr_core
#: model:ir.actions.act_window,name:itr_core.action_itr_case_assignment_log
#: model:ir.ui.menu,name:itr_core.menu_itr_case_assignment_log
msgid "Assignment Log"
msgstr "تاریخچهٔ ارجاع‌ها"

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "Only a CEO (group_ceo member) can be selected as the orderer of a trade case."
msgstr "فقط مدیرعامل (عضو گروه CEO) می‌تواند به‌عنوان دستوردهندهٔ پرونده انتخاب شود."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "The case state can only change through its official transition actions, never by writing the field directly."
msgstr "وضعیت پرونده فقط از طریق اکشن‌های رسمی گذار تغییر می‌کند؛ نوشتن مستقیم فیلد وضعیت ممنوع است."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "The orderer of the case is locked after the first save and can never be changed."
msgstr "دستوردهندهٔ پرونده پس از اولین ثبت قفل می‌شود و هرگز قابل تغییر نیست."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "Illegal state change: %(old)s -> %(new)s is not in the official transition table of the trade case."
msgstr "گذار غیرمجاز وضعیت: انتقال %(old)s به %(new)s در جدول رسمی انتقال پرونده وجود ندارد."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "Leaving the signature step without the scanned, signed document is blocked (G03). Upload the scan first."
msgstr "خروج از مرحلهٔ امضا بدون بارگذاری اسکن سند امضاشده مسدود است (G03). ابتدا اسکن سند را بارگذاری کنید."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "A deal rejection requires a mandatory reason."
msgstr "رد معامله بدون ثبت دلیل اجباری ممکن نیست."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "A deficiency return requires a mandatory reason."
msgstr "بازگشت برای نقص مدارک بدون ثبت دلیل اجباری ممکن نیست."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "A reassignment always requires a mandatory reason."
msgstr "ارجاع مجدد همیشه نیازمند ثبت دلیل اجباری است."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "A supervisor may only assign work to a member of his own team (SEC-004)."
msgstr "سرپرست فقط می‌تواند کار را به عضو تیم خودش ارجاع دهد (SEC-004)."

#. module: itr_core
#: code:addons/itr_core/models/itr_trade_case.py:0
#, python-format
msgid "Segregation of duties: the user who created the case cannot approve it (SEC-015)."
msgstr "تفکیک وظایف: کاربری که پرونده را ساخته نمی‌تواند خودش آن را تأیید کند (SEC-015)."

#. module: itr_core
#: code:addons/itr_core/models/itr_case_assignment_log.py:0
#, python-format
msgid "Assignment log records are append-only and cannot be deleted."
msgstr "رکوردهای تاریخچهٔ ارجاع فقط افزودنی هستند و حذف نمی‌شوند."

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__draft
msgid "Draft"
msgstr "پیش‌نویس"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__waiting_supply
msgid "Waiting for supply"
msgstr "در انتظار تأمین کالا"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__legal_review
msgid "Legal review"
msgstr "بررسی حقوقی"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__treasury_review
msgid "Treasury review"
msgstr "بررسی خزانه"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__receivables_review
msgid "Receivables review"
msgstr "بررسی وصول مطالبات"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__pending_signature
msgid "Pending physical signature"
msgstr "در انتظار امضای فیزیکی"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__approved
msgid "Approved (signed)"
msgstr "تأییدشده (امضاشده)"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__slips_issued
msgid "Sales slips issued"
msgstr "ریزفاکتورهای فروش صادرشده"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__closed
msgid "Closed"
msgstr "مختومه"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__rejected
msgid "Rejected (terminal)"
msgstr "ردشده (قطعی)"

#. module: itr_core
#: model:ir.model.fields.selection,name:itr_core.selection__itr_trade_case__state__returned
msgid "Returned for completion"
msgstr "بازگشتی برای تکمیل مدارک"
"""
    changed.append("i18n/fa_IR.po + phase-4 block")
write(path, text)

print("PATCH_RESULT changed=%d" % len(changed))
for item in changed:
    print(" - " + item)
PYEOF
PATCH_RC=$?
[[ ${PATCH_RC} -eq 0 ]] || err "پچ افزایشی فایل‌های مشترک شکست خورد — طبق C2 هیچ نصب انجام نمی‌شود (rollback: ${P4_BACKUP_DIR}/${TS})"
cp -f "${MOD_DIR}/i18n/fa_IR.po" "${MOD_DIR}/i18n/fa.po"
gate "G4-04" "پچ افزایشی idempotent فایل‌های مشترک بدون بازنویسی فاز ۳ (C2)" "PASS" "backup=${P4_BACKUP_DIR}/${TS}"

# =============================================================================
step "5) verify مستقل فاز ۴ (ops/verify/verify_phase4.py) — کاربر واقعی، بدون sudo"
# =============================================================================
write_utf8 "${OPS_DIR}/verify/verify_phase4.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Independent verify of Phase 4 (V4-01 .. V4-10).

Runs through odoo shell (ADR-005), asserts with the REAL seeded users of
phase 3 (never Administrator - G01/Q15) and rolls back at the end, so it
leaves zero footprint.
"""
import base64
import sys
import traceback

from odoo.exceptions import UserError, ValidationError

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
    Log = env["itr.notification.dispatch.log"]

    def new_case(pattern="buy_first", purchase_rate=100.0):
        return Case.with_user(fin_user).create({
            "requested_by": ceo.id,
            "deal_pattern": pattern,
            "item_ids": [(0, 0, {
                "name": "TEST verify coil",
                "row_kind": "both",
                "contract_tonnage": 50.0,
                "purchase_price_unit": purchase_rate,
                "sale_price_unit": 120.0,
            })],
        })

    # V4-01: sequence + four-tab model exists
    case = new_case()
    chk("V4-01", "پروندهٔ بازرگانی با Sequence خودکار ساخته شد (4.1)",
        bool(case.id) and case.name.startswith("TC/"), case.name)

    # V4-02: non-CEO requested_by refused (server constraint, raw call)
    refused = False
    try:
        Case.with_user(fin_user).create({
            "requested_by": fin_user.id,
            "item_ids": [(0, 0, {"name": "TEST", "contract_tonnage": 1.0})],
        })
    except ValidationError:
        refused = True
    chk("V4-02", "انتخاب غیر-مدیرعامل در requested_by از مسیر API رد شد (4.2)", refused)

    # V4-03: direct state write refused (SEC-016), even as sudo
    blocked_rpc = blocked_sudo = False
    try:
        case.with_user(fin_user).write({"state": "approved"})
    except UserError:
        blocked_rpc = True
    try:
        case.sudo().write({"state": "approved"})
    except UserError:
        blocked_sudo = True
    chk("V4-03", "تغییر مستقیم state از RPC و حتی sudo مسدود است (4.5/SEC-016)",
        blocked_rpc and blocked_sudo)

    # V4-04: pattern A chain to the signature + critical event exactly before it
    case.with_user(fin_user).action_submit()
    case.with_user(legal).action_legal_approve()
    case.with_user(treasury).action_treasury_approve()
    case.with_user(receivables).action_receivables_approve()
    rows = Log.sudo().search([
        ("event_key", "=", "trade_case.back_to_finance_supervisor"),
        ("res_model", "=", "itr.trade.case"), ("res_id", "=", case.id),
    ])
    chk("V4-04", "الگوی A تا امضا + رویداد حیاتی یک قدم پیش از میز سرپرست (4.7/UAT-07)",
        case.state == "pending_signature" and bool(rows)
        and ceo.id in rows.mapped("recipient_user_id").ids,
        "state=%s rows=%d" % (case.state, len(rows)))

    # V4-05: exit without signed document blocked; with document passes (4.8)
    guard = False
    try:
        case.with_user(fin_sup).action_confirm_signed()
    except UserError:
        guard = True
    case.with_context(itr_trade_state_engine=True).write({
        "signed_document": base64.b64encode(b"TEST verify scan"),
        "signed_document_filename": "signed.pdf",
    })
    case.with_user(fin_sup).action_confirm_signed()
    chk("V4-05", "گارد امضا: خروج بدون سند مسدود، با سند آزاد (4.8/G03)",
        guard and case.state == "approved" and all(case.item_ids.mapped("rate_locked")))

    # V4-06: single money engine equals the form roll-up (4.9/UAT-08)
    totals = env["itr.money.engine"].case_totals(case)
    chk("V4-06", "عدد فرم == عدد موتور مالی واحد (4.9/FIN-005)",
        abs(case.estimated_profit_base - totals["estimated_profit"]) < 0.01,
        "profit=%s" % totals["estimated_profit"])

    # V4-07: pattern B parks; no sales slip model exists (4.4/BR-004)
    case_b = new_case(pattern="sell_first", purchase_rate=0.0)
    case_b.with_user(fin_user).action_submit()
    no_slip = "itr.sales.slip" not in env
    early = False
    try:
        case_b.with_user(fin_user).action_supply_ready()
    except UserError:
        early = True
    case_b.item_ids.write({"purchase_price_unit": 90.0})
    case_b.with_user(fin_user).action_supply_ready()
    chk("V4-07", "الگوی B: توقف در انتظار تأمین، بدون هیچ ریزفاکتور، سپس ادامه (4.4)",
        no_slip and early and case_b.state == "legal_review")

    # V4-08: rejection is terminal + deal.rejected dispatched (4.6/G02)
    case_r = new_case()
    case_r.with_user(fin_user).action_submit()
    case_r.with_user(legal).action_legal_reject(reason="TEST verify rejection")
    rows_r = Log.sudo().search([
        ("event_key", "=", "deal.rejected"),
        ("res_model", "=", "itr.trade.case"), ("res_id", "=", case_r.id),
    ])
    back = False
    try:
        case_r.with_user(fin_user).action_resubmit()
    except UserError:
        back = True
    chk("V4-08", "رد معامله: مختومهٔ قطعی + اعلان فوری + عدم بازگشت به مالی (4.6/G02)",
        case_r.state == "rejected" and bool(rows_r) and back)

    # V4-09: alias case.result_to_ceo reaches the official event (UAT-07)
    alias_result = env["itr.notification.service"].with_user(fin_sup).with_context(
        itr_notify_sync=True).notify(
        "case.result_to_ceo", "itr.trade.case", case.id,
        {"occurrence_id": "verify-alias-%s" % case.id})
    chk("V4-09", "alias قدیمی case.result_to_ceo به رویداد رسمی می‌رسد (UAT-07)",
        alias_result.get("reason") == "ok", alias_result.get("reason"))

    # V4-10: assignment = activity + append-only log; out-of-team refused (C1)
    case_a = new_case()
    case_a.with_user(fin_user).action_submit()
    out_refused = False
    try:
        case_a.with_user(fin_sup).assign_to(transport_docs, reason="TEST out of team")
    except UserError:
        out_refused = True
    case_a.with_user(fin_sup).assign_to(fin_user, reason="TEST verify assignment")
    log_rows = case_a.assignment_log_ids.filtered(lambda r: r.to_user_id == fin_user)
    act_rows = env["mail.activity"].sudo().search([
        ("res_model", "=", "itr.trade.case"), ("res_id", "=", case_a.id),
        ("user_id", "=", fin_user.id),
    ])
    del_refused = False
    try:
        log_rows[:1].sudo().unlink()
    except UserError:
        del_refused = True
    chk("V4-10", "ارجاع = مالک + Activity + لاگ افزودنی؛ خارج تیم رد شد (C1/UX-004/SEC-004)",
        out_refused and bool(log_rows) and bool(act_rows) and del_refused)

except Exception as error:  # noqa: BLE001
    traceback.print_exc()
    failed += 1
    checks.append(("V4-ERR", "FAIL", "verify crashed", str(error)))

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
log "ops/verify/verify_phase4.py نوشته شد"

# =============================================================================
step "6) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
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
  gate "G4-05" "نحو پایتون/XML/CSV ماژول سالم است" "PASS" "pre-install static check"
else
  gate "G4-05" "نحو پایتون/XML/CSV ماژول سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب (rollback: ${P4_BACKUP_DIR}/${TS})"
fi

# =============================================================================
step "7) ارتقای ماژول itr_core (بخش دوم) روی ${DB_NAME} (Q01/NFR-001)"
# =============================================================================
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
MOD_STATE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${MOD_STATE_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${MOD_STATE_AFTER}" == "installed" ]]; then
  gate "G4-06" "ارتقای itr_core (فاز ۴) بدون خطا" "PASS" "state=installed rc=0"
else
  gate "G4-06" "ارتقای itr_core (فاز ۴) بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} state=${MOD_STATE_AFTER} → ${INSTALL_LOG}"
  tail -n 60 "${INSTALL_LOG}"
fi

# ساختار دیتابیس: جدول‌ها، sequence، رویدادهای seed و alias
TBL_CASE="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_trade_case')")"
TBL_ITEM="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_trade_case_item')")"
TBL_SHORT="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_factory_shortfall')")"
TBL_ASSIGN="$(q "${DB_NAME}" "SELECT to_regclass('public.itr_case_assignment_log')")"
SEQ_OK="$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code='itr.trade.case'")"
EV_BACK="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key='trade_case.back_to_finance_supervisor' AND is_critical IS TRUE")"
EV_REJ="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event WHERE event_key='deal.rejected'")"
ALIAS_OK="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_alias WHERE alias_key='case.result_to_ceo'")"
SHORT_UNIQ="$(q "${DB_NAME}" "SELECT count(*) FROM pg_indexes WHERE tablename='itr_factory_shortfall' AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%trade_case_item_id%'")"
echo "case=${TBL_CASE} item=${TBL_ITEM} shortfall=${TBL_SHORT} assign=${TBL_ASSIGN} seq=${SEQ_OK} ev_back=${EV_BACK} ev_rej=${EV_REJ} alias=${ALIAS_OK} shortfall_uniq=${SHORT_UNIQ}"
if [[ "${TBL_CASE}" == "itr_trade_case" && "${TBL_ITEM}" == "itr_trade_case_item" \
      && "${TBL_SHORT}" == "itr_factory_shortfall" && "${TBL_ASSIGN}" == "itr_case_assignment_log" \
      && "${SEQ_OK}" == "1" && "${EV_BACK}" == "1" && "${EV_REJ}" == "1" \
      && "${ALIAS_OK}" == "1" && "${SHORT_UNIQ}" -ge 1 ]]; then
  gate "G4-07" "مدل‌ها/Sequence/رویدادها/alias/کلید یکتای BR-121 ساخته شدند (4.1/4.7/4.10)" "PASS" \
       "4 tables, seq=1, critical event + alias, unique(item) index"
else
  gate "G4-07" "مدل‌ها/Sequence/رویدادها/alias/کلید یکتای BR-121 ساخته شدند" "FAIL" \
       "case=${TBL_CASE} item=${TBL_ITEM} short=${TBL_SHORT} assign=${TBL_ASSIGN} seq=${SEQ_OK} back=${EV_BACK} rej=${EV_REJ} alias=${ALIAS_OK} uniq=${SHORT_UNIQ}"
fi

# =============================================================================
step "8) تست‌های خودکار Odoo — فاز ۴ *و* بازاجرای فاز ۳ (Q04 + اثبات C2)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G4-08" "تست‌های خودکار فاز ۴ و بازاجرای فاز ۳ سبز هستند" "FAIL" "SKIP_TESTS=1 (طبق Q04 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "${MODULE}" --test-enable --test-tags "/${MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  # [FIX-3] فقط شکست واقعی unittest شمرده می‌شود (FAIL: TestClass.test_... /
  # ERROR: TestClass.test_...)؛ خطای SQL موردانتظار «duplicate key» در test_26
  # اثبات کارکرد قید BR-121 است و شکست تست نیست (در اجرای قبل rc=0 بود ولی
  # grep قبلی آن را fails=1 شمرد و G4-08 را قرمز کرد).
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" && -n "${TEST_TOTAL}" ]]; then
    gate "G4-08" "تست‌های فاز ۴ سبز + تست‌های فاز ۳ دوباره سبز (فاز ۳ نشکست — C2)" "PASS" "${TEST_TOTAL:-tests} rc=0"
  else
    gate "G4-08" "تست‌های خودکار فاز ۴ و بازاجرای فاز ۳ سبز هستند" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-none} → ${TEST_LOG}"
    grep -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_|At least one test failed|Traceback \(most recent' "${TEST_LOG}" | head -n 20 || true
    echo "--- expected-constraint-noise (not a failure, for audit) ---"
    grep -E 'duplicate key value violates unique constraint' "${TEST_LOG}" | head -n 5 || true
  fi
fi

# =============================================================================
step "9) verify مستقل V4-01..V4-10 (بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G4-09" "verify مستقل فاز ۴ سبز است (V4-01..V4-10)" "FAIL" "SKIP_VERIFY=1 (طبق Q15 اجباری است)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" \
    --log-level=warn --stop-after-init <"${OPS_DIR}/verify/verify_phase4.py" \
    >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^ITR_VERIFY ' "${VERIFY_LOG}" || true
  VERIFY_LINE="$(grep -E '^ITR_VERIFY_RESULT:' "${VERIFY_LOG}" | tail -n1 || true)"
  echo "${VERIFY_LINE}"
  if echo "${VERIFY_LINE}" | grep -q 'ITR_VERIFY_RESULT: PASS'; then
    gate "G4-09" "verify مستقل فاز ۴ سبز است (V4-01..V4-10)" "PASS" "${VERIFY_LINE}"
  else
    gate "G4-09" "verify مستقل فاز ۴ سبز است (V4-01..V4-10)" "FAIL" "${VERIFY_LINE:-خروجی یافت نشد} (rc=${VERIFY_RC}) → ${VERIFY_LOG}"
    tail -n 40 "${VERIFY_LOG}"
  fi
fi

# =============================================================================
step "10) گاردهای معماری فاز ۴ (G18 تک‌موتور مالی/کارتابل + Q05 + G01 + Q03)"
# =============================================================================
# گارد ۱: فقط یک موتور مالی — هیچ فرمول سود دومی خارج money_engine (FIN-005/G18)
PROFIT_HITS="$(grep -rnE 'estimated_profit|sales_base *-.*purchase_base' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v '/itr_core/models/money_engine.py' | grep -v '/itr_core/models/itr_trade_case.py' | grep -v '/tests/' | grep -v '/ops/verify/' || true)"
if [[ -z "${PROFIT_HITS}" ]]; then
  gate "G4-10" "فقط یک موتور محاسبهٔ سود در کل مخزن (4.9/FIN-005/G18)" "PASS" "itr_core/models/money_engine.py"
else
  gate "G4-10" "فقط یک موتور محاسبهٔ سود در کل مخزن (4.9/FIN-005/G18)" "FAIL" "$(echo "${PROFIT_HITS}" | head -n3 | tr '\n' ' ')"
fi

# گارد ۲: هیچ موتور Task/صف کار دومی ساخته نشد (C1/G18) — فقط لاگ افزودنی مجاز
TASK_HITS="$(grep -rnE '_name = "itr\.(task|work\.queue|todo)' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
if [[ -z "${TASK_HITS}" ]]; then
  gate "G4-11" "هیچ موتور Task/صف کار دوم ساخته نشد؛ فقط پایهٔ state+owner+log (C1/G18)" "PASS" "clean"
else
  gate "G4-11" "هیچ موتور Task/صف کار دوم ساخته نشد (C1/G18)" "FAIL" "$(echo "${TASK_HITS}" | head -n3 | tr '\n' ' ')"
fi

# گارد ۳: sudo() فقط با مجوز صریح
SUDO_HITS="$(grep -rn --include='*.py' '\.sudo(' "${MOD_DIR}/models" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G4-12" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/SEC-018)" "PASS" "models/ تمیز"
else
  gate "G4-12" "هیچ sudo() بدون مجوز صریح در منطق ماژول (G01/SEC-018)" "FAIL" "$(echo "${SUDO_HITS}" | head -n3 | tr '\n' ' ')"
fi

# گارد ۴: نام‌های فنی ASCII (فارسی فقط در i18n و فایل‌های data)
NONASCII_PY="$(LC_ALL=C grep -rnE "(_name|_description|string) *= *(\"[^\"]*[^ -~]|'[^']*[^ -~])" --include='*.py' "${MOD_DIR}" 2>/dev/null || true)"
NONASCII_XML="$(LC_ALL=C grep -rnE "(name|string)=\"[^\"]*[^ -~]" --include='*.xml' "${MOD_DIR}/security" "${MOD_DIR}/views" 2>/dev/null | grep -v 'fa_IR' || true)"
if [[ -z "${NONASCII_PY}" && -z "${NONASCII_XML}" ]]; then
  gate "G4-13" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "PASS" "فارسی فقط در i18n/data"
else
  gate "G4-13" "نام‌ها و برچسب‌های فنی کاملاً ASCII (Q05/G19)" "FAIL" "$(echo "${NONASCII_PY}${NONASCII_XML}" | head -n3 | tr '\n' ' ')"
fi

# گارد ۵: Administrator بدون هیچ گروه کسب‌وکاری و بدون مالکیت کارتابل (Q03)
ADMIN_GROUPS="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN res_users u ON u.id=r.uid JOIN ir_model_data d ON d.model='res.groups' AND d.res_id=r.gid AND d.module='itr_core' WHERE u.login='admin'")"
ADMIN_OWNER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_trade_case c JOIN res_users u ON u.id=c.current_owner_id WHERE u.login='admin'")"
if [[ "${ADMIN_GROUPS}" == "0" && "${ADMIN_OWNER:-0}" == "0" ]]; then
  gate "G4-14" "Administrator بدون نقش کسب‌وکاری و بدون هیچ پرونده در کارتابل (Q03/UX-003)" "PASS" "0 group / 0 owned case"
else
  gate "G4-14" "Administrator بدون نقش کسب‌وکاری و بدون هیچ پرونده در کارتابل (Q03/UX-003)" "FAIL" "groups=${ADMIN_GROUPS} owned=${ADMIN_OWNER}"
fi

# =============================================================================
step "11) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
CNT_BEFORE="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code='itr.trade.case'")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core'")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" -u "${MODULE}" \
  --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
CNT_AFTER="$(q "${DB_NAME}" "SELECT count(*) FROM itr_notification_event")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_sequence WHERE code='itr.trade.case'")|$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_data WHERE module='itr_core'")"
echo "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
if [[ ${IDEMP_RC} -eq 0 && "${CNT_BEFORE}" == "${CNT_AFTER}" ]]; then
  gate "G4-15" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "PASS" "events|seq|xmlid = ${CNT_AFTER}"
else
  gate "G4-15" "ارتقای تکراری رکورد تکراری نساخت (Idempotent)" "FAIL" "before=${CNT_BEFORE} after=${CNT_AFTER} rc=${IDEMP_RC}"
fi

# =============================================================================
step "12) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  gate "G4-16" "itr_core (فاز ۴) روی محیط UAT ارتقا یافت" "WARN" "SKIP_UAT=1"
elif [[ ! -f "${CONF_FILE_UAT}" ]] || ! db_exists "${DB_NAME_UAT}"; then
  gate "G4-16" "itr_core (فاز ۴) روی محیط UAT ارتقا یافت" "WARN" "محیط UAT یافت نشد"
else
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  UAT_FLAG="-i"; [[ "${UAT_STATE}" == "installed" ]] && UAT_FLAG="-u"
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    "${UAT_FLAG}" "${MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_AFTER="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${MODULE}'")"
  UAT_CASE_TBL="$(q "${DB_NAME_UAT}" "SELECT to_regclass('public.itr_trade_case')")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_AFTER}" == "installed" && "${UAT_CASE_TBL}" == "itr_trade_case" ]]; then
    gate "G4-16" "itr_core (فاز ۴) روی محیط UAT ارتقا یافت" "PASS" "${DB_NAME_UAT} state=installed"
  else
    gate "G4-16" "itr_core (فاز ۴) روی محیط UAT ارتقا یافت" "FAIL" "rc=${UAT_RC} state=${UAT_AFTER} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "13) اسناد حاکمیتی: ADR (قفل نام state ها — Q11/G10) / REUSE MAP / تحویل"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
touch "${ADR_FILE}"
if ! grep -q "ADR-017" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-017 — قفل رسمی نام‌های وضعیت پروندهٔ بازرگانی (فاز ۴ — G10/Q11)
نام‌های فنی state مدل itr.trade.case از این لحظه قفل هستند و بدون Migration
رسمی هرگز تغییر نمی‌کنند (داشبورد/KPI/کانبان فازهای ۸ و ۹ به آن‌ها وابسته‌اند):
draft | waiting_supply | legal_review | treasury_review | receivables_review |
pending_signature | approved | slips_issued | closed | rejected | returned
جدول انتقال صریح در models/itr_trade_case.py (ALLOWED_TRANSITIONS) تنها مرجع
گذار است؛ نوشتن مستقیم فیلد state حتی با sudo مسدود است (SEC-016).

## ADR-018 — موتور مالی واحد (فاز ۴ — FIN-005/G18)
تنها نقطهٔ محاسبهٔ سود و مبالغ پایه: env['itr.money.engine'] (case_totals /
item_side_base). فرم، داشبورد فاز ۸ و همهٔ گزارش‌های فاز ۹ فقط از همین
می‌خوانند. هر فرمول دوم = Gate قرمز (گارد grep در 004.sh).

## ADR-019 — پایهٔ کارتابل بدون موتور دوم (فاز ۴ — دغدغهٔ C1 / UX-011 / G18)
کارتابل فاز ۸ روی همین سه ستون ساخته می‌شود و لاغیر:
(۱) ماشین‌حالت قفل‌شدهٔ ADR-017، (۲) فیلدهای current_owner_id/owner_deadline،
(۳) ارجاع فقط از متد assign_to() = تغییر مالک + mail.activity استاندارد Odoo
(UX-004) + رکورد append-only در itr.case.assignment.log + پیام Chatter.
واژهٔ «آزادسازی» ممنوع؛ ارجاع سرپرست فقط به عضو تیم خودش (SEC-004) از مدل
itr.supervisor.team فاز ۳. ساخت هر مدل Task/صف موازی در فازهای بعد = Gate قرمز.

## ADR-020 — رویدادهای اعلان بذر فاز ۴ و قرارداد با فاز ۱۰
فاز ۴ فقط رویدادهایی را می‌کارد که چک‌لیست خودش (4.6/4.7) لازم دارد:
trade_case.back_to_finance_supervisor (+alias اجباری case.result_to_ceo)،
deal.rejected، case.parked_waiting_supply، case.legal_rejected،
case.treasury_rejected، case.receivables_rejected، case.signed_and_uploaded.
فاز ۱۰ هنگام سیم‌کشی کاتالوگ کامل باید به همین xmlid ها (itr_core.event_*)
ارجاع/به‌روزرسانی کند و هرگز همان event_key را با xmlid دیگری نسازد
(event_key نمایهٔ یکتای واقعی دیتابیس دارد).

## ADR-021 — پچ افزایشی فایل‌های مشترک به‌جای بازنویسی (فاز ۴ — دغدغهٔ C2)
اسکریپت 004.sh هیچ فایل فاز ۳ را بازنویسی نمی‌کند: فایل‌های جدید جداگانه‌اند و
پنج فایل مشترک (__manifest__.py، models/__init__.py، tests/__init__.py،
security/ir.model.access.csv، i18n/fa_IR.po) فقط «درج در صورت غیاب» می‌شوند
(idempotent). پیش از پچ: پشتیبان DB + کپی timestamp دار فایل‌ها در
docs/phase4-backup/. صحت فاز ۳ پس از فاز ۴ با بازاجرای کامل تست‌های فاز ۳
اثبات می‌شود (Gate G4-08).

## ADR-022 — قیود SQL در Odoo 19 فقط با models.Constraint
Odoo 19 ویژگی `_sql_constraints` را پشتیبانی نمی‌کند (هشدار صریح در لاگ نصب و
عدم ساخت ایندکس). از فاز ۴ به بعد هر قید یکتا/چک پایگاه‌داده در ماژول‌های itr_*
فقط با `models.Constraint` تعریف می‌شود و وجود ایندکس با کوئری مستقیم
pg_indexes اثبات می‌گردد (G4-07، FIN-027، NOT-006).
MDEOF
log "ADR-017..022 به ARCHITECTURE_DECISIONS.md افزوده شد"
else
  if ! grep -q "ADR-022" "${ADR_FILE}"; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-022 — قیود SQL در Odoo 19 فقط با models.Constraint
Odoo 19 ویژگی `_sql_constraints` را پشتیبانی نمی‌کند (هشدار صریح در لاگ نصب و
عدم ساخت ایندکس). از فاز ۴ به بعد هر قید یکتا/چک پایگاه‌داده در ماژول‌های itr_*
فقط با `models.Constraint` تعریف می‌شود و وجود ایندکس با کوئری مستقیم
pg_indexes اثبات می‌گردد (G4-07، FIN-027، NOT-006).
MDEOF
    log "ADR-022 به ARCHITECTURE_DECISIONS.md افزوده شد"
  else
    warn "ADR-017..022 از قبل ثبت شده — بدون تغییر"
  fi
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "itr.money.engine" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## فاز ۴ — itr_core بخش دوم (Q14)
| فاز | چه چیزی بازاستفاده شد | چرا مدل موازی ساخته نشد |
|---|---|---|
| ۴ | `itr.notification.service.notify()` فاز ۲ برای هر ۷ رویداد فاز | تنها نقطهٔ ورود اعلان (NOT-001) |
| ۴ | `itr.notification.alias` فاز ۲ برای case.result_to_ceo | جدول alias تنها مرجع نام‌های قدیمی |
| ۴ | `itr.fx.service.resolve_rate/apply_fx` فاز ۳ برای چندارزی ردیف‌ها | تنها موتور ارز (G12/G18) |
| ۴ | `itr.supervisor.team.get_subordinate_users` فاز ۳ در گارد ارجاع | تنها مدل سلسله‌مراتب سرپرستی (SEC-004) |
| ۴ | `mail.activity` استاندارد Odoo برای ارجاع (UX-004) | موتور Task دوم ممنوع (G18) |
| ۴ | `product.product` هستهٔ Odoo (لینک اختیاری روی ردیف کالا) | ساخت کاتالوگ موازی ممنوع (Q13) |
| ۴ | `ir.sequence` هستهٔ Odoo برای شمارهٔ پرونده | شماره‌ساز دوم ممنوع |

## آنچه فازهای بعد باید از فاز ۴ بازاستفاده کنند (ساخت دوباره = Gate قرمز)
* `itr.trade.case` + جدول انتقال قفل‌شده (ADR-017) → فاز ۵ (ریزفاکتور) از
  `mark_slips_issued()` وارد می‌شود؛ فاز ۶ گذار `slips_issued → closed` را می‌بندد.
* `env['itr.money.engine'].case_totals()` → تنها منبع سود/مبالغ برای داشبورد
  فاز ۸ و گزارش ۲۶ستونهٔ فاز ۹ (UAT-08).
* `current_owner_id` + `owner_deadline` + `assign_to()` + `itr.case.assignment.log`
  → تنها پایهٔ Unified Work Queue و کارتابل ده‌بخشی فاز ۸ (UX-001/UX-011).
* `itr.factory.shortfall` (کلید یکتای شامل ردیف خرید — BR-121) → فاز ۶ منطق
  ایجاد خودکار و تسویهٔ جزئی (BR-122) را اضافه می‌کند، مدل جدید نمی‌سازد.
* فیلدهای `reserved_tonnage`/`effective_tonnage` روی ردیف کالا → فقط فاز ۵ و
  فاز ۶ می‌نویسند؛ گزارش G10 فاز ۹ می‌خواند.

## آنچه فاز ۴ عمداً نساخت (خارج از فاز)
* itr.sales.slip (فاز ۵ — BR-004: در الگوی B حتی پیش‌نویس هم ممنوع بود)
* itr.transport.case، هزینه، پرداخت، بستن (فاز ۶)
* ماتریس نهایی Record Rule «خودم/تیم/همه» (فاز ۷)
* کارتابل ده‌بخشی، Home، مرکز اعلان، داشبورد ۱۸کارته (فاز ۸ — روی پایهٔ ADR-019)
* سیم‌کشی کاتالوگ کامل اعلان و SLA (فاز ۱۰ — طبق ADR-020)
MDEOF
log "docs/REUSE_MAP.md به‌روزرسانی شد"
fi

# =============================================================================
step "14) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" != "1" ]]; then
  gate "G4-17" "سرویس بالا و صفحهٔ ورود HTTP 200" "WARN" "START_DAEMON=0"
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
    gate "G4-17" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200 pid=$(cat "${PID_FILE}" 2>/dev/null || echo '-')"
  else
    gate "G4-17" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE} → ${LOG_FILE}"
  fi
fi

# =============================================================================
step "15) ثبت Git + تگ phase-4 (Q09) + اسکن رمز (Q12)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "تغییری برای commit نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-4: itr_core part 2 (trade case, locked state machine, 3-station reviews, signature guard, single money engine, shortfall skeleton, cartable foundation)"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-4 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-4 || true
fi
GIT_HEAD="$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
GIT_TAG="$(git -C "${CUSTOM_ADDONS}" tag --points-at HEAD | tr '\n' ' ' || true)"
if [[ "${GIT_HEAD}" != "n/a" ]]; then
  gate "G4-18" "Git commit و تگ فاز ثبت شد (Q09)" "PASS" "HEAD=${GIT_HEAD} tags=${GIT_TAG:-phase-4}"
else
  gate "G4-18" "Git commit و تگ فاز ثبت شد (Q09)" "FAIL" "commit ثبت نشد"
fi

SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z | xargs -0 -r grep -nIE '(as12|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]|password[[:space:]]*=[[:space:]]*[^[:space:]])' 2>/dev/null | grep -v 'secrets.env.example' | grep -v 'ARCHITECTURE_DECISIONS.md' | grep -v 'test_itr' | grep -v 'test_notify' | grep -v 'required_fields' | grep -v 'itr_core_users_data.xml' || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G4-19" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "PASS" "clean"
else
  gate "G4-19" "هیچ رمز/کلید تازه‌ای وارد Git نشد (Q12/NFR-004)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 4 — گزارش پذیرش فاز ۴"
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

write_utf8 "${DOC_DIR}/PHASE4-DELIVERY.md" <<MDEOF
# تحویل فاز ۴ — itr_core بخش دوم (پیوست ب نقشهٔ راه)

- تاریخ اجرا: $(date -Is)
- Odoo: ${ODOO_V}
- پایگاه‌دادهٔ توسعه: ${DB_NAME} | پذیرش: ${DB_NAME_UAT}
- Commit: ${GIT_HEAD} | Tag: phase-4
- وضعیت Gate 4: **${GATE_STATUS}** (هشدار: ${WARNS})

## ۱) Scope انجام‌شده (با شناسهٔ نیازمندی)
| بند | شرح | شناسه |
|---|---|---|
| 4.1 | itr.trade.case با چهار تب + Sequence خودکار + mail.thread/activity | REQ-001، بخش ۳ |
| 4.2 | requested_by: دامنهٔ کلاینتی + Constraint سرور (فقط CEO) + قفل پس از ثبت | SEC-016 |
| 4.3 | itr.trade.case.item با ابعاد/ضخامت/تناژ + چهار فیلد چندارزی هر سمت + row_kind | G11، G12، FIN-011..014 |
| 4.4 | دو الگوی A/B؛ در الگوی B هیچ itr.sales.slip حتی پیش‌نویس (مدل تا فاز ۵ وجود ندارد) | BR-003/004 |
| 4.5 | ماشین‌حالت با جدول انتقال صریح + انسداد write مستقیم state حتی sudo | G10، SEC-016، ADR-017 |
| 4.6 | سه ایستگاه حقوقی/خزانه/وصول با سه خروجی مجزا + notify('deal.rejected') فوری | G02 |
| 4.7 | notify('trade_case.back_to_finance_supervisor') یک قدم پیش از میز سرپرست + alias case.result_to_ceo | UAT-07 |
| 4.8 | گارد امضا سمت سرور: ورود آزاد، خروج بدون signed_document مسدود | G03 |
| 4.9 | موتور مالی واحد itr.money.engine؛ roll-up سربرگ فقط‌خواندنی و آمادهٔ فاز ۹ | FIN-005، G18، UAT-08 |
| 4.10 | اسکلت itr.factory.shortfall با کلید یکتای شامل trade_case_item_id (models.Constraint) | BR-121، ADR-022 |
| 4.11 | Kanban وضعیت‌محور با رنگ‌بندی؛ drag&drop گذار نمی‌سازد | UX-063 |
| C1 | پایهٔ کارتابل: current_owner + assign_to() + activity + لاگ افزودنی + گارد تیم | UX-004/011، SEC-004، ADR-019 |
| C2 | پچ افزایشی فایل‌های مشترک + fingerprint قرارداد + بازاجرای تست‌های فاز ۳ | NFR-002، پیوست ج، ADR-021 |

## ۲) Scope خارج از فاز (عمداً انجام نشد)
ریزفاکتور فروش و ایجاد خودکار حمل (فاز ۵)، عملیات حمل/هزینه/پرداخت/بستن
(فاز ۶)، ماتریس نهایی Record Rule (فاز ۷)، کارتابل ده‌بخشی/Home/داشبورد
(فاز ۸ — روی پایهٔ ADR-019)، گزارش‌ها (فاز ۹)، کاتالوگ کامل اعلان/SLA (فاز ۱۰).

## ۳) فایل‌های ایجادشده (جدید) و پچ‌شده (افزایشی)
\`\`\`
[NEW] ${MODULE}/models/{money_engine.py, itr_trade_case.py, itr_trade_case_item.py,
                        itr_case_assignment_log.py, itr_factory_shortfall.py}
[NEW] ${MODULE}/security/itr_core_phase4_rules.xml
[NEW] ${MODULE}/data/{itr_trade_case_data.xml, itr_core_notify_events.xml}
[NEW] ${MODULE}/views/{itr_trade_case_views.xml, itr_factory_shortfall_views.xml,
                       itr_case_assignment_views.xml, itr_core_phase4_menus.xml}
[NEW] ${MODULE}/tests/test_trade_case_phase4.py
[NEW] ops/verify/verify_phase4.py
[PATCH] ${MODULE}/__manifest__.py (data+depends+version — درج فقط در صورت غیاب)
[PATCH] ${MODULE}/models/__init__.py , tests/__init__.py (append idempotent)
[PATCH] ${MODULE}/security/ir.model.access.csv (append idempotent)
[PATCH] ${MODULE}/i18n/fa_IR.po + fa.po (بلاک با marker)
پشتیبان فایل‌های مشترک: docs/phase4-backup/${TS}/
\`\`\`

## ۴) ماتریس دسترسی تغییرکرده (خلاصه)
| مدل | user | fin_user | fin_sup | ایستگاه‌ها | ceo | auditor |
|---|---|---|---|---|---|---|
| itr.trade.case | r | rwcu | rwc | rw | rwc | r |
| itr.trade.case.item | r | rwcu | rwcu | - | rwc | - |
| itr.factory.shortfall | r | rwc | rwc | - | rwc | - |
| itr.case.assignment.log | r+c (append-only در مدل) | همان | همان | همان | همان | r |

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
# بازگشت کامل به وضعیت پیش از فاز ۴:
bash ops/restore.sh <آخرین dump پیش از فاز> <آخرین filestore.tar.gz> ${DB_NAME}
git -C ${CUSTOM_ADDONS} checkout phase-3 -- ${MODULE}
# یا فقط فایل‌های مشترک: کپی از docs/phase4-backup/${TS}/
\`\`\`

## ۸) گام بعد
Gate 4 سبز ⇒ آغاز فاز ۵ (itr.sales.slip منحصراً پس از امضا + ایجاد خودکار
idempotent پروندهٔ حمل با قفل تراکنشی — ورود از mark_slips_issued همین فاز).
MDEOF

git -C "${CUSTOM_ADDONS}" add -A >/dev/null 2>&1 || true
git -C "${CUSTOM_ADDONS}" commit -q -m "phase-4: delivery report" >/dev/null 2>&1 || true

cat <<FINAL

============================================================
 script-04-itr-core-trade.sh (004.sh) به پایان رسید
------------------------------------------------------------
 ماژول        : itr_core (بخش دوم: پروندهٔ بازرگانی + تأییدات + امضا)
 ماشین‌حالت   : ۱۱ وضعیت قفل‌شده (ADR-017) + جدول انتقال صریح + انسداد RPC
 تأییدات      : حقوقی → خزانه → وصول (تأیید / نقص→مالی / رد→مختومه+پیامک)
 رویداد حیاتی : trade_case.back_to_finance_supervisor (+alias case.result_to_ceo)
 گارد امضا    : خروج بدون سند امضاشده مسدود (G03) + قفل نرخ اقلام (FIN-014)
 موتور مالی   : itr.money.engine — تنها نقطهٔ محاسبه (FIN-005/G18)
 دفتر طلب     : itr.factory.shortfall (اسکلت، کلید BR-121 با models.Constraint)
 پایهٔ کارتابل: current_owner + assign_to + activity + لاگ افزودنی (C1/ADR-019)
 ایمنی فاز ۳  : پچ افزایشی + پشتیبان + بازاجرای تست‌های فاز ۳ (C2/ADR-021)
 verify       : ${OPS_DIR}/verify/verify_phase4.py
 گزارش تحویل  : ${DOC_DIR}/PHASE4-DELIVERY.md
 Git          : HEAD=${GIT_HEAD}  tag=phase-4
 گام بعدی     : فاز ۵ (ریزفاکتور فروش + ایجاد خودکار پروندهٔ حمل)
============================================================
FINAL

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 4 = سبز ✅ (هشدار: ${WARNS}) — مجاز به شروع فاز ۵.${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 4 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۵ آغاز نمی‌شود.${NC}\n"
  exit 1
fi
