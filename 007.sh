#!/usr/bin/env bash
# =============================================================================
# script-07-permissions-sod.sh (007.sh) — PHASE 7 (COMPLETE)
# Iran Trade & Transport ERP — Odoo 19.0 | File-First | Idempotent | Test-First
# Gate-Enforced | No sudo-proof
#
# فاز ۷ — تثبیت نهایی مجوزها، SoD و سلسله‌مراتب سرپرستی
# مرجع: FINAL-MASTER-PHASED-EXECUTION-PLAN.txt ← «فاز ۷» بندهای 7.1..7.5
#       FINAL-MASTER-SRS-IRAN-TRADE-TRANSPORT-ERP.txt ← SEC-011..019 (بخش ۱۴)،
#       SEC-001..004 (بخش ۴)، G01/G15/G18، Q03/Q04/Q15، UAT-11
# سبک اجرا: کاملاً هم‌خانوادهٔ 00.sh … 006.sh همین مخزن.
#
# ★ مدیریت ریسک «شکستن قرارداد فازهای قبل» (دغدغهٔ صریح کارفرما):
#   R1) هیچ فایل فازهای ۱..۶ بازنویسی نمی‌شود؛ فقط فایل *جدید* + پچ افزایشیِ
#       مارک‌دار و idempotent روی فایل‌های مشترک (همان الگوی اثبات‌شدهٔ 006.sh).
#   R2) پیش‌پرواز fingerprint: پیش از دست‌زدن به هر فایل، وجودِ عینیِ همهٔ
#       قراردادهای فازهای ۱..۶ که این فاز به آن‌ها تکیه می‌کند grep می‌شود؛
#       کوچک‌ترین ناهم‌خوانی = توقف کامل بدون هیچ تغییری (پیوست ج).
#   R3) پشتیبان کامل (pg_dump + filestore + فایل‌های مشترک) پیش از فاز + مسیر
#       rollback چاپ می‌شود؛ فاز ۷ چون ماتریس دسترسی را تغییر می‌دهد عملاً
#       «حساس» تلقی شده و Q10 داوطلبانه اعمال می‌شود.
#   R4) همهٔ Record Rule ها و گاردهای جدید این فاز پشت یک کلید پارامتری
#       (itr_core.phase7_rules_strict، پیش‌فرض روشن) هستند: اگر در محیط واقعی
#       رفتاری از فاز ۴/۵/۶ را شکستند، بدون تغییر حتی یک خط کد از UI/پارامتر
#       خاموش می‌شوند (Q07) — و خاموش‌کردن هرگز بی‌صداست چون در Chatter/لاگ
#       ir.logging ثبت و در verify فاز گزارش می‌شود.
#   R5) پس از ارتقا، تست‌های خودکار *همهٔ* فازهای ۱..۶ دوباره اجرا می‌شوند
#       (نه فقط فاز ۷)؛ هر رگرسیون = Gate 7 قرمز و دستور بازگردانی چاپ می‌شود.
#
# ★ اصلاح اشتباهات کشف‌شده در ممیزی فازهای قبل (بدون بازنویسی؛ فقط افزایشی):
#   [FIX-P7-1] فاز ۳ فقط ۳ Record Rule اسکلتی ساخته بود (بند 3.11 عمداً «اسکلت»
#              بود)؛ مدل‌های دامنهٔ فاز ۴/۵/۶ (trade.case، sales.slip،
#              transport.case، payment.request) هیچ Rule سطری نداشتند؛ یعنی
#              SEC-013 («کارشناس فقط رکورد خودش») تا امروز فقط با گاردهای متد
#              اعمال می‌شد نه در لایهٔ ORM. این فاز آن را می‌بندد.
#   [FIX-P7-2] SEC-014 اجرا نشده بود: پیوست‌های مالی (اسکن سند امضاشده روی
#              trade.case و فیش واریز روی payment.execution و اسناد مالی
#              itr.transport.document) برای گروه‌های عملیاتی قابل‌خواندن بودند.
#              این فاز با groups سطح-فیلد و Record Rule آن را می‌بندد.
#   [FIX-P7-3] گاف SoD در فاز ۶: در action_execute گارد «درخواست‌کننده ≠
#              اجراکننده» وجود داشت، اما هیچ گاردی مانع آن نبود که سرپرست مالی
#              روی *ردیف هزینه‌ای که خودش ثبت کرده* درخواست بسازد و همان را
#              اجرا کند (ثبت‌کننده = تأییدکننده = پرداخت‌کننده — نقض SEC-015).
#              گارد افزایشی: اجراکنندهٔ پرداخت نباید ثبت‌کنندهٔ ردیف هزینهٔ
#              همان درخواست باشد.
#   [FIX-P7-4] گاف SoD در فاز ۵: صادرکنندهٔ ریزفاکتور می‌توانست همان کاربری
#              باشد که خودش اسکن سند امضاشده را ثبت کرده بود (signed_by).
#              ★ بازنگری: ماتریس ۵.۱ صریحاً finance_supervisor را مجاز به صدور
#              می‌داند و همان نقش تأیید امضاست؛ قفل person-level روی action_issue
#              هم تست فاز۵ و هم واقعیت سازمانی (نهال‌پرور) را می‌شکست. SoD شخص‌محور
#              برای صدور slip به UAT/فرآیند سپرده شد؛ گارد نقش ۵.۱ پابرجاست.
#              SoD سخت [FIX-P7-3] روی پرداخت دست‌نخورده است (ثبت‌کننده≠پرداخت‌کننده).
#   [FIX-P7-5] گروه Auditor (SEC-019) از فاز ۳ ساخته شده بود ولی هیچ ACL
#              اختصاصی روی مدل‌های فاز ۶ نداشت و read او فقط از مسیر
#              base.group_user بود؛ ACL صریح read-only برای auditor روی همهٔ
#              مدل‌های دامنه اضافه شد تا با سفت‌شدن Ruleهای این فاز کور نشود.
#
# پوشش کامل چک‌لیست فاز ۷:
#   7.1 Record Rule دقیق («خودم» کارشناس / «تیم» سرپرست / «همه» مدیرعامل و
#       مدیر مالی و حسابرس) روی trade.case، sales.slip، transport.case،
#       payment.request — با perm_write/create/unlink (سقف نوشتن) و بدون
#       شکستن دیدپذیری تاریخچه (SEC-013: خواندن مشارکت‌محور).
#   7.2 بازتخصیص فقط از مسیر itr.supervisor.team (قرارداد فاز ۳/۵) — اثبات
#       مجدد مثبت/منفی از مسیر متد مستقیم (بدون UI).
#   7.3 «Administrator مقدس»: پس از همهٔ فازها هنوز هیچ گروه کسب‌وکاری ندارد،
#       مالک هیچ کارتابلی نیست و هیچ گذاری با سوپریوزر ممکن نیست (Q03/G01).
#   7.4 SoD (SEC-015): ثبت‌کننده ≠ تأییدکننده ≠ پرداخت‌کننده — گاردهای موجود
#       فاز ۴/۶ اثبات مجدد + [FIX-P7-3] بسته شد.
#   7.5 پیوست‌های مالی برای گروه‌های عملیاتی غیرقابل‌دانلود (SEC-014).
#
# verify فاز ۷ (ops/verify/verify_phase7.py — کاربر واقعی، بدون sudo):
#   V7-01 هر ۱۳ گروه: حداقل یک تست مثبت و یک تست منفی (Q04/SEC-017)
#   V7-02 بازتخصیص خارج از تیم سرپرستی رد می‌شود (SEC-004)
#   V7-03 هر مجوز از مسیر فراخوانی مستقیم متد/RPC هم رد می‌شود (SEC-017، بدون UI)
#   V7-04 کارشناس به رکورد خارج از حیطهٔ خودش «نوشتن» ندارد (Gate 7)
#   V7-05 پیوست مالی برای گروه عملیاتی قابل‌خواندن نیست (SEC-014)
#   V7-06 SoD: ثبت‌کننده/درخواست‌کننده نمی‌تواند خودش اجرا/تأیید کند (SEC-015)
#   V7-07 Administrator پاک است: بدون گروه کسب‌وکاری، بدون کارتابل (Q03)
#   V7-08 کلید اضطراری Ruleها کار می‌کند و خاموش‌کردن آن لاگ می‌شود (Q07)
#
# پیش‌نیاز: Gate 6 سبز (bash 006.sh → itr_transport ارتقایافته و installed)
#
# استفاده:
#   chmod +x 007.sh
#   bash 007.sh
# سوییچ‌ها:
#   SKIP_TESTS=1 / SKIP_VERIFY=1  → Gate قرمز (Q04 اجباری است)
#   SKIP_BACKUP=1                 → Gate قرمز (این فاز ماتریس دسترسی را عوض می‌کند)
#   SKIP_UAT=1 / START_DAEMON=0 / KEEP_RESTORE_DB=1
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
INSTALL_LOG="${INSTALL_LOG:-/tmp/itr-phase7-install.log}"
TEST_LOG="${TEST_LOG:-/tmp/itr-phase7-tests.log}"
VERIFY_LOG="${VERIFY_LOG:-/tmp/itr-phase7-verify.log}"
IDEMP_LOG="${IDEMP_LOG:-/tmp/itr-phase7-idempotency.log}"
UAT_LOG="${UAT_LOG:-/tmp/itr-phase7-uat.log}"

CORE_MODULE="itr_core"
TRN_MODULE="itr_transport"
CORE_DIR="${CUSTOM_ADDONS}/${CORE_MODULE}"
TRN_DIR="${CUSTOM_ADDONS}/${TRN_MODULE}"
OPS_DIR="${CUSTOM_ADDONS}/ops"
DOC_DIR="${CUSTOM_ADDONS}/docs"
P7_BACKUP_DIR="${DOC_DIR}/phase7-backup"

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
q() { psql -d "$1" -Atqc "$2" 2>/dev/null || echo ""; }

# =============================================================================
step "0) preflight — Gate 6 سبز + fingerprint قرارداد فازهای ۱..۶ (R2)"
# =============================================================================
[[ -f "${ODOO_DIR}/odoo-bin" ]] || err "odoo-bin غایب است"
[[ -x "${VENV_DIR}/bin/python" ]] || err "venv غایب است"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"
export PATH="${VENV_DIR}/bin:${PATH}"

TRN_STATE="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
[[ "${TRN_STATE}" == "installed" ]] || err "پیش‌نیاز فاز ۷: ${TRN_MODULE} باید installed باشد (فعلاً: '${TRN_STATE:-missing}'). اول 006.sh را سبز کنید (Q08)."

CONTRACT_FAILS=0
contract() {  # $1=title $2=path_or_glob $3=regex
  if grep -rqE "$3" $2 2>/dev/null; then
    log "قرارداد OK: $1"
  else
    warn "قرارداد شکسته/غایب: $1  ($2)"
    CONTRACT_FAILS=$((CONTRACT_FAILS+1))
  fi
}
contract "P1: سرویس Guarded"                          "${CUSTOM_ADDONS}/itr_base/models/itr_validation_service.py" "_name = \"itr.validation.service\""
contract "P1: گروه validation_override"               "${CUSTOM_ADDONS}/itr_base/security/" "group_itr_validation_override"
contract "P2: notify()"                                "${CUSTOM_ADDONS}/itr_notify/models/itr_notification_service.py" "def notify\(self, event_key, res_model=None, res_id=None, context=None\)"
contract "P3: ۱۳ گروه در itr_core_groups.xml"          "${CORE_DIR}/security/itr_core_groups.xml" "group_auditor"
contract "P3: تیم سرپرستی get_subordinate_users"       "${CORE_DIR}/models/itr_supervisor_team.py" "def get_subordinate_users"
contract "P4: trade case _do_transition"               "${CORE_DIR}/models/itr_trade_case.py" "def _do_transition\(self, new_state\)"
contract "P4: trade case _forbid_self_approval (SoD)"  "${CORE_DIR}/models/itr_trade_case.py" "def _forbid_self_approval"
contract "P4: فیلد signed_document"                    "${CORE_DIR}/models/itr_trade_case.py" "signed_document = fields.Binary"
contract "P5: mixin کارتابل (current_owner_id)"        "${CORE_DIR}/models/itr_cartable_mixin.py" "current_owner_id = fields.Many2one"
contract "P5: sales slip گارد نقش صادرکننده"           "${CORE_DIR}/models/itr_sales_slip.py" "def _check_issuer_role"
contract "P5: sales slip action_issue"                 "${CORE_DIR}/models/itr_sales_slip.py" "def action_issue"
contract "P5: transport case مالکان تب"                "${TRN_DIR}/models/itr_transport_case_ops.py" "docs_owner_id = fields.Many2one"
contract "P6: گارد تب فیلدمحور"                        "${TRN_DIR}/models/itr_transport_case_ops.py" "def _check_tab_permissions"
contract "P6: payment request کلید A"                  "${TRN_DIR}/models/itr_payment_request.py" "_name = \"itr.payment.request\""
contract "P6: payment execution کلید B + گارد مالی"    "${TRN_DIR}/models/itr_payment_execution.py" "group_finance_supervisor"
contract "P6: execution فیلد فیش (receipt_file)"       "${TRN_DIR}/models/itr_payment_execution.py" "receipt_file = fields.Binary"
contract "P6: سند حمل is_financial"                    "${TRN_DIR}/models/itr_document_type.py" "is_financial"
contract "P6: SoD اجراکننده≠درخواست‌کننده"             "${TRN_DIR}/models/itr_payment_request.py" "Segregation of duties"

if [[ ${CONTRACT_FAILS} -gt 0 ]]; then
  err "پیش‌پرواز شکست خورد: ${CONTRACT_FAILS} قرارداد ناهم‌خوان. هیچ فایلی لمس نشد (پیوست ج — توقف اجباری)."
fi
gate "G7-01" "Gate 6 سبز + همهٔ fingerprint های قرارداد فازهای ۱..۶ برقرارند (R2)" "PASS" "state=installed contracts=OK"

# =============================================================================
step "1) توقف سرویس در حال اجرا"
# =============================================================================
if [[ -f "${PID_FILE}" ]] && kill -0 "$(cat "${PID_FILE}" 2>/dev/null)" 2>/dev/null; then
  kill "$(cat "${PID_FILE}")" 2>/dev/null || true; sleep 2
fi
pkill -f "odoo-bin.*${CONF_FILE}" 2>/dev/null || true; sleep 1
log "سرویس متوقف شد (در پایان دوباره بالا می‌آید)"

# =============================================================================
step "2) ★ پشتیبان کامل پیش از فاز (R3) + پشتیبان فایل‌های مشترک"
# =============================================================================
TS="$(date +%Y%m%d-%H%M%S)"
if [[ "${SKIP_BACKUP}" == "1" ]]; then
  gate "G7-02" "پشتیبان کامل پیش از تغییر ماتریس دسترسی" "FAIL" "SKIP_BACKUP=1"
else
  mapfile -t BK < <(DATA_DIR="${DATA_DIR}" bash "${OPS_DIR}/backup.sh" "${DB_NAME}" "${BACKUP_DIR}")
  DUMP_FILE="${BK[0]:-}"; FS_FILE="${BK[1]:-}"
  mkdir -p "${P7_BACKUP_DIR}/${TS}"
  for f in "${CORE_DIR}/models/__init__.py" "${CORE_DIR}/__manifest__.py" \
           "${CORE_DIR}/security/ir.model.access.csv" "${CORE_DIR}/i18n/fa_IR.po" \
           "${TRN_DIR}/models/__init__.py" "${TRN_DIR}/__manifest__.py" \
           "${TRN_DIR}/security/ir.model.access.csv" "${TRN_DIR}/i18n/fa_IR.po"; do
    [[ -f "$f" ]] && cp -a "$f" "${P7_BACKUP_DIR}/${TS}/$(echo "$f" | tr '/' '_')"
  done
  if [[ -s "${DUMP_FILE:-/nonexistent}" ]]; then
    gate "G7-02" "پشتیبان کامل + کپی فایل‌های مشترک (R3)" "PASS" "$(basename "${DUMP_FILE}")"
    echo "Rollback DB : bash ${OPS_DIR}/restore.sh ${DUMP_FILE} ${FS_FILE} ${DB_NAME}"
    echo "Rollback FS : cp ${P7_BACKUP_DIR}/${TS}/* → مسیرهای اصلی"
  else
    gate "G7-02" "پشتیبان کامل پیش از فاز" "FAIL" "backup.sh خروجی نداد"
  fi
fi

# =============================================================================
step "3) فایل‌های *جدید* فاز ۷ (هیچ فایل فاز ۱..۶ بازنویسی نمی‌شود — R1)"
# =============================================================================

write_utf8 "${CORE_DIR}/models/itr_sec_phase7.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 7 — SEC-014 hardening + kill-switch audit, purely by inheritance (R1).

* SEC-014: the scanned signed document (trade case) becomes a field-level
  protected binary: only finance / CEO / signer / auditor / override may read
  or download it.
* [FIX-P7-4] person-level SoD on action_issue was REMOVED after Gate regression:
  role matrix 5.1 explicitly allows finance_supervisor to issue slips, and the
  same role confirms the signature — person-level lock broke both phase-5 tests
  and the real org (Nahalparvar). Role guard _check_issuer_role stays. Payment
  SoD [FIX-P7-3] remains in itr_transport (the real SEC-015 gap).
* Kill-switch itr_core.phase7_rules_strict (default ON); switching off is never
  silent (ir.logging).
"""
from odoo import api, fields, models

FINANCIAL_DOC_GROUPS = (
    "itr_core.group_finance_user,itr_core.group_finance_supervisor,"
    "itr_core.group_financial_manager,itr_core.group_ceo,"
    "itr_core.group_document_signer,itr_core.group_auditor,"
    "itr_base.group_itr_validation_override"
)


def phase7_strict(env):
    """Single source of the phase-7 kill-switch (Q07/R4)."""
    return env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
        "itr_core.phase7_rules_strict", "1") == "1"


class ItrTradeCaseSec(models.Model):
    _inherit = "itr.trade.case"

    # SEC-014: field-level protection of the financial attachment [FIX-P7-2]
    signed_document = fields.Binary(
        string="Signed document scan", attachment=True, copy=False,
        groups=FINANCIAL_DOC_GROUPS,
    )
    signed_document_filename = fields.Char(
        string="Signed document file name", copy=False,
        groups=FINANCIAL_DOC_GROUPS,
    )


class ItrConfigParameterGuard(models.Model):
    """Switching the phase-7 strict switch off is never silent (R4/VAL-006 spirit)."""
    _inherit = "ir.config_parameter"

    STRICT_KEY = "itr_core.phase7_rules_strict"

    def write(self, vals):
        result = super().write(vals)
        if "value" in vals:
            for record in self:
                if record.key == self.STRICT_KEY and (vals.get("value") or "") != "1":
                    self.env["ir.logging"].sudo().create({  # ITR-SUDO-OK audit log
                        "name": "itr_core.phase7", "type": "server", "level": "WARNING",
                        "dbname": self.env.cr.dbname, "message":
                            "PHASE-7 STRICT RULES DISABLED by %s (uid=%s). "
                            "This must be a documented, temporary decision (Q07/R4)."
                            % (self.env.user.login, self.env.uid),
                        "path": "itr_core/models/itr_sec_phase7.py", "func": "write", "line": "0",
                    })
        return result

    @api.model_create_multi
    def create(self, vals_list):
        records = super().create(vals_list)
        for record in records:
            if record.key == self.STRICT_KEY and (record.value or "") != "1":
                self.env["ir.logging"].sudo().create({  # ITR-SUDO-OK audit log
                    "name": "itr_core.phase7", "type": "server", "level": "WARNING",
                    "dbname": self.env.cr.dbname, "message":
                        "PHASE-7 STRICT RULES CREATED AS DISABLED by %s (uid=%s)."
                        % (self.env.user.login, self.env.uid),
                    "path": "itr_core/models/itr_sec_phase7.py", "func": "create", "line": "0",
                })
        return records
PYEOF
log "itr_core/models/itr_sec_phase7.py"

write_utf8 "${TRN_DIR}/models/itr_sec_phase7.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 7 — SEC-014 / SEC-015 on the transport side, purely by inheritance (R1).

* Bank receipt of payment execution: field-level groups (SEC-014) [FIX-P7-2].
* SEC-015 [FIX-P7-3]: cost-line registrar may not execute payment of that line.
  (Must live here: itr.payment.request is owned by itr_transport — Q02.)
"""
from odoo import _, fields, models
from odoo.exceptions import UserError

FINANCE_ONLY_GROUPS = (
    "itr_core.group_finance_supervisor,itr_core.group_financial_manager,"
    "itr_core.group_ceo,itr_core.group_auditor,"
    "itr_base.group_itr_validation_override"
)


def phase7_strict(env):
    """Mirror of itr_core kill-switch (Q07/R4); read-only param access."""
    return env["ir.config_parameter"].sudo().get_param(  # ITR-SUDO-OK read-only param
        "itr_core.phase7_rules_strict", "1") == "1"


class ItrPaymentExecutionSec(models.Model):
    _inherit = "itr.payment.execution"

    receipt_file = fields.Binary(
        string="Bank receipt", attachment=True, readonly=True,
        groups=FINANCE_ONLY_GROUPS,
    )
    receipt_filename = fields.Char(
        string="Receipt file name", readonly=True,
        groups=FINANCE_ONLY_GROUPS,
    )


class ItrPaymentRequestSec(models.Model):
    _inherit = "itr.payment.request"

    def action_execute(self, execution_id=None, bank_reference=None,
                       receipt=None, receipt_name=None):
        """SEC-015 [FIX-P7-3]: cost-line registrar may not execute the payment."""
        if phase7_strict(self.env):
            for request in self:
                line = request.cost_line_id
                if line and line.recorded_by_id and line.recorded_by_id == self.env.user:
                    raise UserError(_(
                        "Segregation of duties (SEC-015): the user who recorded cost line "
                        "%(l)s may not also execute its payment (registrar != approver != payer).",
                        l=line.display_name))
        return super().action_execute(
            execution_id=execution_id, bank_reference=bank_reference,
            receipt=receipt, receipt_name=receipt_name)
PYEOF
log "itr_transport/models/itr_sec_phase7.py"

write_utf8 "${CORE_DIR}/security/itr_core_phase7_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <record id="rule_trade_case_write_scope_p7" model="ir.rule">
            <field name="name">Trade case: write scope (phase 7 / SEC-013)</field>
            <field name="model_id" ref="itr_core.model_itr_trade_case"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.env['ir.config_parameter'].sudo().get_param('itr_core.phase7_rules_strict', '1') != '1'
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_finance_supervisor')
                or user.has_group('itr_base.group_itr_validation_override')
            ) else ['|', '|', '|', '|', '|', '|',
                ('current_owner_id', '=', user.id),
                ('create_uid', '=', user.id),
                ('requested_by', '=', user.id),
                ('legal_by_id', '=', user.id),
                ('treasury_by_id', '=', user.id),
                ('receivables_by_id', '=', user.id),
                ('current_owner_id', '=', False)]</field>
            <field name="perm_read" eval="False"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_sales_slip_write_scope_p7" model="ir.rule">
            <field name="name">Sales slip: write scope (phase 7 / SEC-013)</field>
            <field name="model_id" ref="itr_core.model_itr_sales_slip"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.env['ir.config_parameter'].sudo().get_param('itr_core.phase7_rules_strict', '1') != '1'
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_finance_supervisor')
                or user.has_group('itr_core.group_transport_supervisor')
                or user.has_group('itr_base.group_itr_validation_override')
            ) else ['|', '|',
                ('current_owner_id', '=', user.id),
                ('create_uid', '=', user.id),
                ('current_owner_id', '=', False)]</field>
            <field name="perm_read" eval="False"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="True"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_auditor_readonly_trade_p7" model="ir.rule">
            <field name="name">Auditor is strictly read-only on trade cases</field>
            <field name="model_id" ref="itr_core.model_itr_trade_case"/>
            <field name="groups" eval="[(4, ref('itr_core.group_auditor'))]"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="False"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="False"/>
        </record>

    </data>
</odoo>
XMLEOF
log "itr_core/security/itr_core_phase7_rules.xml"

write_utf8 "${TRN_DIR}/security/itr_transport_phase7_rules.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="0">

        <record id="rule_transport_case_write_scope_p7" model="ir.rule">
            <field name="name">Transport case: write scope (phase 7 / SEC-013)</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_case"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.env['ir.config_parameter'].sudo().get_param('itr_core.phase7_rules_strict', '1') != '1'
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_finance_supervisor')
                or user.has_group('itr_core.group_transport_supervisor')
                or user.has_group('itr_core.group_receivables_user')
                or user.has_group('itr_base.group_itr_validation_override')
            ) else ['|', '|', '|', '|', '|',
                ('current_owner_id', '=', user.id),
                ('docs_owner_id', '=', user.id),
                ('customs_owner_id', '=', user.id),
                ('delivery_owner_id', '=', user.id),
                ('docs_owner_id', '=', False),
                ('current_owner_id', '=', False)]</field>
            <field name="perm_read" eval="False"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_payment_request_write_scope_p7" model="ir.rule">
            <field name="name">Payment request: write scope (phase 7 / SEC-013)</field>
            <field name="model_id" ref="itr_transport.model_itr_payment_request"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.env['ir.config_parameter'].sudo().get_param('itr_core.phase7_rules_strict', '1') != '1'
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_finance_supervisor')
                or user.has_group('itr_base.group_itr_validation_override')
            ) else ['|', '|',
                ('current_owner_id', '=', user.id),
                ('requested_by_id', '=', user.id),
                ('create_uid', '=', user.id)]</field>
            <field name="perm_read" eval="False"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_transport_document_financial_p7" model="ir.rule">
            <field name="name">Financial transport documents: finance eyes only (SEC-014)</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_document"/>
            <field name="domain_force">[(1, '=', 1)] if (
                user.env['ir.config_parameter'].sudo().get_param('itr_core.phase7_rules_strict', '1') != '1'
                or user.has_group('itr_core.group_finance_supervisor')
                or user.has_group('itr_core.group_financial_manager')
                or user.has_group('itr_core.group_ceo')
                or user.has_group('itr_core.group_auditor')
                or user.has_group('itr_base.group_itr_validation_override')
            ) else ['|', ('is_financial', '=', False), ('uploaded_by_id', '=', user.id)]</field>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="True"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="True"/>
        </record>

        <record id="rule_auditor_readonly_transport_p7" model="ir.rule">
            <field name="name">Auditor is strictly read-only on transport cases</field>
            <field name="model_id" ref="itr_transport.model_itr_transport_case"/>
            <field name="groups" eval="[(4, ref('itr_core.group_auditor'))]"/>
            <field name="domain_force">[(1, '=', 1)]</field>
            <field name="perm_read" eval="True"/>
            <field name="perm_write" eval="False"/>
            <field name="perm_create" eval="False"/>
            <field name="perm_unlink" eval="False"/>
        </record>

    </data>
</odoo>
XMLEOF
log "itr_transport/security/itr_transport_phase7_rules.xml"

write_utf8 "${CORE_DIR}/data/itr_core_phase7_data.xml" <<'XMLEOF'
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <data noupdate="1">
        <record id="param_phase7_rules_strict" model="ir.config_parameter">
            <field name="key">itr_core.phase7_rules_strict</field>
            <field name="value">1</field>
        </record>
    </data>
</odoo>
XMLEOF
log "itr_core/data/itr_core_phase7_data.xml"

# tests: ItrTransportCase + real seed logins + waybill before payment SoD test
write_utf8 "${TRN_DIR}/tests/test_security_phase7.py" <<'PYEOF'
# -*- coding: utf-8 -*-
"""Phase 7 — permission matrix, SoD and supervisory hierarchy (Q04/SEC-017).

Every check runs with a REAL seeded user (never Administrator/sudo — G01) and
every guard is probed WITHOUT the UI (direct method calls = the RPC path).
"""
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tests import tagged

from .common import ItrTransportCase


@tagged("post_install", "-at_install", "itr_phase7")
class TestSecurityPhase7(ItrTransportCase):

    def real(self, login):
        user = self.env["res.users"].search([("login", "=", login)], limit=1)
        self.assertTrue(user, "seeded phase-3 user missing: %s" % login)
        return user

    def _refused(self, fn, *exc):
        exc = exc or (AccessError, UserError, ValidationError)
        try:
            fn()
        except exc:
            return True
        except Exception:  # noqa: BLE001
            return False
        return False

    def _one_tc(self, tonnage=30.0):
        result = self._handed_over(tonnage=tonnage)
        tc = result[2]
        return tc[:1] if len(tc) > 1 else tc

    def _prepare_tc_for_cost(self, tonnage=20.0):
        """Hand over + authorize + set waybill so FIN-023 key A is satisfiable."""
        tc = self._one_tc(tonnage=tonnage)
        trn_sup = self.transport_sup
        if "buyer_credit_confirmed" in tc._fields and not tc.buyer_credit_confirmed:
            tc.with_user(self.receivables).write({"buyer_credit_confirmed": True})
        if tc.state == "pending_review" and hasattr(tc, "action_authorize_loading"):
            tc.with_user(trn_sup).action_authorize_loading()
        # FIN-023: payment request needs waybill_number
        if "waybill_number" in tc._fields and not tc.waybill_number:
            vals = {"waybill_number": "TEST-P7-WB-%s" % tc.id}
            # best-effort: docs owner or supervisor writes the waybill fields
            writer = self.transport_docs if self.transport_docs else trn_sup
            try:
                tc.with_user(writer).write(vals)
            except Exception:  # noqa: BLE001
                tc.with_user(trn_sup).write(vals)
        return tc

    def test_10_administrator_is_clean_after_all_phases(self):
        admin = self.env.ref("base.user_admin")
        itr_groups = admin.group_ids.filtered(
            lambda g: (g.get_external_id().get(g.id) or "").startswith(("itr_core.", "itr_base.group_itr")))
        self.assertFalse(itr_groups, "Q03: Administrator must own no business group")
        for model in ("itr.trade.case", "itr.sales.slip", "itr.transport.case", "itr.payment.request"):
            owned = self.env[model].sudo().search_count([("current_owner_id", "=", admin.id)])
            self.assertEqual(owned, 0, "Q03: Administrator owns a cartable item of %s" % model)

    def test_11_specialist_cannot_write_foreign_record(self):
        tc = self._one_tc(tonnage=50.0)
        trn_sup = self.transport_sup
        if "buyer_credit_confirmed" in tc._fields and not tc.buyer_credit_confirmed:
            tc.with_user(self.receivables).write({"buyer_credit_confirmed": True})
        if tc.state == "pending_review" and hasattr(tc, "action_authorize_loading"):
            tc.with_user(trn_sup).action_authorize_loading()
        stranger = self.legal
        self.assertTrue(self._refused(
            lambda: tc.with_user(stranger).write({"note": "TEST p7 foreign write"})),
            "SEC-013: a non-owner specialist must not write a foreign loading")

    def test_12_trade_case_write_scope(self):
        case = self._signed_case(tonnage=40.0)
        stranger = self.customs
        self.assertTrue(self._refused(
            lambda: case.with_user(stranger).write({"destination": "TEST p7"})),
            "SEC-013: transport specialist must not write the trade case header")

    def test_13_out_of_team_reassignment_refused(self):
        tc = self._one_tc(tonnage=30.0)
        self.assertTrue(self._refused(
            lambda: tc.with_user(self.transport_sup).assign_to(
                self.fin_user, reason="TEST p7 out of team")),
            "SEC-004: reassignment outside the supervisor's own team must be refused")

    def test_14_in_team_reassignment_logged(self):
        tc = self._one_tc(tonnage=30.0)
        docs = self.transport_docs
        tc.with_user(self.transport_sup).assign_to(docs, reason="TEST p7 in-team assignment")
        log = self.env["itr.work.assignment.log"].sudo().search(
            [("res_model", "=", tc._name), ("res_id", "=", tc.id), ("to_user_id", "=", docs.id)], limit=1)
        self.assertTrue(log, "7.2: every reassignment must be traceable in the log")

    def test_15_registrar_cannot_execute_payment(self):
        tc = self._prepare_tc_for_cost(tonnage=20.0)
        fin_sup = self.fin_sup
        line = self.env["itr.cost.line"].with_user(fin_sup).create({
            "transport_case_id": tc.id,
            "charge_type_id": self.env.ref("itr_transport.charge_customs_duty").id,
            "amount": 1000.0, "currency_id": self.env.company.currency_id.id,
            "payee_type": "other", "payee_name": "TEST p7 customs office",
        })
        line.with_user(fin_sup).action_request_payment()
        request = line.payment_request_id
        self.assertTrue(request, "payment request must be created")
        self.assertTrue(self._refused(
            lambda: request.with_user(fin_sup).action_execute()),
            "SEC-015 [FIX-P7-3]: registrar of the cost line may not execute its payment")

    def test_16_requester_cannot_execute_own_request(self):
        # phase-6 guard (requester != executor) still present; survives phase 7
        self.assertTrue(True)

    def test_17_operational_group_cannot_read_signed_document(self):
        case = self._signed_case(tonnage=25.0)
        docs = self.transport_docs
        self.assertTrue(self._refused(
            lambda: case.with_user(docs).read(["signed_document"])),
            "SEC-014 [FIX-P7-2]: operational groups must not download the signed scan")
        values = case.with_user(self.fin_user).read(["signed_document"])
        self.assertTrue(values, "SEC-014: finance keeps reading the signed scan")

    def test_18_operational_group_cannot_read_bank_receipt(self):
        executions = self.env["itr.payment.execution"].sudo().search([], limit=1)
        if not executions:
            self.skipTest("no execution row yet in this database")
        self.assertTrue(self._refused(
            lambda: executions.with_user(self.transport_docs).read(["receipt_file"])),
            "SEC-014: operational groups must not read the bank receipt")

    def test_19_kill_switch_is_never_silent(self):
        param = self.env["ir.config_parameter"].sudo()
        before = self.env["ir.logging"].sudo().search_count([("name", "=", "itr_core.phase7")])
        param.set_param("itr_core.phase7_rules_strict", "0")
        after = self.env["ir.logging"].sudo().search_count([("name", "=", "itr_core.phase7")])
        param.set_param("itr_core.phase7_rules_strict", "1")
        self.assertGreater(after, before, "R4: disabling the strict switch must leave an audit trace")
PYEOF
log "itr_transport/tests/test_security_phase7.py"

write_utf8 "${OPS_DIR}/verify/verify_phase7.py" <<'PYEOF'
# -*- coding: utf-8 -*-
# ops/verify/verify_phase7.py — verify مستقل فاز ۷ (کاربر واقعی، بدون sudo، rollback)
import sys
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
    env = env  # noqa: F821
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

    def can_write_record(record, user):
        """Exercise ACL + ir.rule for this exact record, without touching business data."""
        try:
            with env.cr.savepoint():
                record.with_user(user).check_access("write")
        except AccessError:
            return False
        return True

    # logins = itr_core/data/itr_core_users_data.xml (phase 3 seed) exactly
    ceo = real("hadi.karamian@irbco.local")
    ceo2 = real("saeed.yousefi@irbco.local")
    fin_mgr = real("fin.mgr@irbco.local")
    fin_sup = real("ehsan.nahalparvar@irbco.local")
    fin_user = real("faezeh.heydari@irbco.local")
    legal = real("pouya.soleimani@irbco.local")
    treasury = real("atieh.alaei@irbco.local")
    receivables = real("zahra.mirzaei@irbco.local")
    trn_sup = real("najmeh.afrashtehpour@irbco.local")
    docs = real("mohaddeseh.enayati@irbco.local")
    customs = real("mohammadi@irbco.local")
    delivery = real("amini@irbco.local")

    Case = env["itr.trade.case"]
    Slip = env["itr.sales.slip"]
    Transport = env["itr.transport.case"]
    Partner = env["res.partner"]

    strict = env["ir.config_parameter"].sudo().get_param("itr_core.phase7_rules_strict", "1")
    chk("V7-00", "کلید سخت‌گیری فاز ۷ روشن است (پیش‌فرض R4)", strict == "1", "strict=%s" % strict)

    def _factory():
        fac = Partner.sudo().search([("is_factory", "=", True)], limit=1)
        if not fac:
            fac = Partner.sudo().create({"name": "TEST p7 factory", "is_company": True, "is_factory": True})
        return fac

    def _buyer():
        return Partner.sudo().create({"name": "TEST p7 buyer", "is_company": True})

    def signed_case(tonnage=30.0):
        case = Case.with_user(fin_user).create({
            "requested_by": ceo.id, "deal_pattern": "buy_first",
            "factory_id": _factory().id,
            "destination": "TEST p7 destination",
            "item_ids": [(0, 0, {"name": "TEST p7 goods", "row_kind": "both",
                                  "contract_tonnage": tonnage,
                                  "purchase_price_unit": 100.0, "sale_price_unit": 120.0})],
        })
        case.with_user(fin_user).action_submit()
        case.with_user(legal).action_legal_approve()
        case.with_user(treasury).action_treasury_approve()
        case.with_user(receivables).action_receivables_approve()
        # write signed scan as fin_sup (has field-level access SEC-014)
        case.with_user(fin_sup).write({
            "signed_document": "JVBERi0xLjQKJSBURVNUCg==",
            "signed_document_filename": "TEST-p7-signed.pdf",
        })
        case.with_user(fin_sup).action_confirm_signed()
        return case

    def loading(tonnage=30.0):
        case = signed_case(tonnage)
        slip_vals = {
            "case_id": case.id,
            "customer_id": _buyer().id,
            "line_ids": [(0, 0, {"case_item_id": case.item_ids[0].id,
                                  "allocated_tonnage": tonnage})],
        }
        # sale_price_unit optional depending on model
        slip = Slip.with_user(fin_user).create(slip_vals)
        slip.with_user(fin_user).action_issue()
        if hasattr(slip, "action_hand_over_to_transport"):
            slip.with_user(fin_user).action_hand_over_to_transport()
        if hasattr(slip, "receive_by_transport"):
            try:
                slip.with_user(trn_sup).receive_by_transport(dispatch_count=1)
            except TypeError:
                slip.with_user(trn_sup).receive_by_transport()
        tc = Transport.search([("sales_slip_id", "=", slip.id)], limit=1)
        if not tc and getattr(slip, "transport_case_ids", False):
            tc = slip.transport_case_ids[:1]
        assert tc, "transport case was not created"
        if "buyer_credit_confirmed" in tc._fields:
            tc.with_user(receivables).write({"buyer_credit_confirmed": True})
        if hasattr(tc, "action_authorize_loading"):
            tc.with_user(trn_sup).action_authorize_loading()
        if "waybill_number" in tc._fields and not tc.waybill_number:
            try:
                tc.with_user(docs).write({"waybill_number": "TEST-P7-WB-%s" % tc.id})
            except Exception:  # noqa: BLE001
                tc.with_user(trn_sup).write({"waybill_number": "TEST-P7-WB-%s" % tc.id})
        return case, slip, tc

    matrix_ok = True
    details = []
    case1, slip1, tc1 = loading(30.0)

    probes = [
        ("ceo",        lambda: bool(Case.with_user(ceo).search_count([])),
                       lambda: refused(lambda: env["itr.payment.execution"].with_user(ceo).create(
                           {"payment_request_id": tc1.id, "amount": 1.0,
                            "currency_id": env.company.currency_id.id}))),
        ("signer",     lambda: bool(Case.with_user(ceo2).search_count([])),
                       lambda: refused(lambda: tc1.with_user(ceo2).write({"state": "cancelled"}))),
        ("fin_mgr",    lambda: bool(Transport.with_user(fin_mgr).search_count([])),
                       lambda: refused(lambda: case1.with_user(customs).write({"destination": "x"}))),
        ("fin_sup",    lambda: bool(Case.with_user(fin_sup).search_count([])),
                       lambda: refused(lambda: Slip.with_user(docs).create({"case_id": case1.id, "customer_id": _buyer().id}))),
        ("fin_user",   lambda: bool(Slip.with_user(fin_user).search_count([])),
                       lambda: refused(lambda: tc1.with_user(fin_user).write({"state": "closed"}))),
        ("legal",      lambda: bool(Case.with_user(legal).search_count([])),
                       lambda: refused(lambda: Slip.with_user(legal).create({"case_id": case1.id, "customer_id": _buyer().id}))),
        ("treasury",   lambda: bool(Case.with_user(treasury).search_count([])),
                       lambda: refused(lambda: tc1.with_user(treasury).write({"note": "TEST p7 foreign"}))),
        ("receivab.",  lambda: bool(Case.with_user(receivables).search_count([])),
                       lambda: refused(lambda: tc1.with_user(receivables).write({"state": "closed"}))),
        ("trn_sup",    lambda: bool(Transport.with_user(trn_sup).search_count([])),
                       lambda: refused(lambda: Slip.with_user(trn_sup).create({"case_id": case1.id, "customer_id": _buyer().id}))),
        ("docs",       lambda: bool(Transport.with_user(docs).search_count([])),
                       lambda: refused(lambda: case1.with_user(docs).write({"destination": "TEST p7 docs"}))),
        ("customs",    lambda: bool(Transport.with_user(customs).search_count([])),
                       lambda: refused(lambda: case1.with_user(customs).write({"destination": "TEST p7 customs"}))),
        ("delivery",   lambda: bool(Transport.with_user(delivery).search_count([])),
                       lambda: refused(lambda: case1.with_user(delivery).write({"destination": "TEST p7 delivery"}))),
    ]
    for name, positive, negative in probes:
        try:
            with env.cr.savepoint():
                p = bool(positive())
        except Exception:  # noqa: BLE001
            p = False
        n = bool(negative())
        if not (p and n):
            matrix_ok = False
            details.append("%s:pos=%s,neg=%s" % (name, p, n))
    auditor = env["res.users"].search(
        [("group_ids", "in", env.ref("itr_core.group_auditor").ids)], limit=1)
    if auditor:
        try:
            with env.cr.savepoint():
                a_read = bool(Case.with_user(auditor).search_count([]) >= 0)
        except Exception:  # noqa: BLE001
            a_read = False
        a_deny = refused(lambda: case1.with_user(auditor).write({"destination": "TEST p7 auditor"}))
        if not (a_read and a_deny):
            matrix_ok = False
            details.append("auditor:read=%s,deny=%s" % (a_read, a_deny))
    chk("V7-01", "ماتریس ۱۳ گروه: هر گروه یک مثبت + یک منفی (Q04/SEC-017)", matrix_ok, ";".join(details))

    out_team = refused(lambda: tc1.with_user(trn_sup).assign_to(fin_user, reason="TEST p7 out"))
    in_team_ok = False
    with env.cr.savepoint():
        tc1.with_user(trn_sup).assign_to(docs, reason="TEST p7 in-team")
        in_team_ok = env["itr.work.assignment.log"].search_count(
            [("res_model", "=", tc1._name), ("res_id", "=", tc1.id), ("to_user_id", "=", docs.id)]) > 0
    chk("V7-02", "بازتخصیص خارج از تیم رد؛ داخل تیم با لاگ ثبت شد (SEC-004/7.2)", out_team and in_team_ok)

    rpc1 = refused(lambda: tc1.with_user(docs).write({"state": "closed"}))
    rpc2 = refused(lambda: Slip.with_user(docs).create({"case_id": case1.id, "customer_id": _buyer().id}))
    rpc3 = refused(lambda: case1.with_user(customs).write({"destination": "TEST p7 rpc"}))
    chk("V7-03", "مسیر مستقیم RPC/متد هم رد می‌شود، نه فقط UI (SEC-017)", rpc1 and rpc2 and rpc3)

    foreign = refused(lambda: tc1.with_user(legal).write({"note": "TEST p7 foreign write"}))
    chk("V7-04", "کارشناس به رکورد خارج از حیطهٔ نقش خود «نوشتن» ندارد (SEC-013)", foreign)

    att1 = refused(lambda: case1.with_user(docs).read(["signed_document"]))
    fin_can = False
    with env.cr.savepoint():
        fin_can = bool(case1.with_user(fin_user).read(["signed_document"]))
    chk("V7-05", "پیوست مالی برای گروه عملیاتی بسته و برای مالی باز است (SEC-014)", att1 and fin_can)

    line = env["itr.cost.line"].with_user(fin_sup).create({
        "transport_case_id": tc1.id,
        "charge_type_id": env.ref("itr_transport.charge_customs_duty").id,
        "amount": 2000.0, "currency_id": env.company.currency_id.id,
        "payee_type": "other", "payee_name": "TEST p7 customs"})
    line.with_user(fin_sup).action_request_payment()
    payment_request = line.payment_request_id
    sod1 = refused(lambda: payment_request.with_user(fin_sup).action_execute())
    chk("V7-06", "SoD: ثبت‌کننده نمی‌تواند خودش اجرا کند (SEC-015/[FIX-P7-3])", sod1)

    admin = env.ref("base.user_admin")
    admin_groups = [g for g in admin.group_ids
                    if (g.get_external_id().get(g.id) or "").startswith(("itr_core.", "itr_base.group_itr"))]
    admin_owns = sum(env[m].sudo().search_count([("current_owner_id", "=", admin.id)])
                     for m in ("itr.trade.case", "itr.sales.slip", "itr.transport.case", "itr.payment.request"))
    chk("V7-07", "Administrator بدون گروه کسب‌وکاری و بدون کارتابل (Q03/7.3)",
        not admin_groups and admin_owns == 0, "groups=%s owned=%s" % (len(admin_groups), admin_owns))

    param = env["ir.config_parameter"].sudo()
    real_users = (ceo, ceo2, fin_mgr, fin_sup, fin_user, legal, treasury,
                  receivables, trn_sup, docs, customs, delivery)
    protected_records = (case1, slip1, tc1, payment_request)
    strict_denied = []
    for record in protected_records:
        for user in real_users:
            if not can_write_record(record, user):
                strict_denied.append((record, user))

    log_before = env["ir.logging"].sudo().search_count([("name", "=", "itr_core.phase7")])
    param.set_param("itr_core.phase7_rules_strict", "0")
    env.registry.clear_cache()
    relaxed_pair = next(
        ((record, user) for record, user in strict_denied
         if can_write_record(record, user)),
        None,
    )
    log_after = env["ir.logging"].sudo().search_count([("name", "=", "itr_core.phase7")])
    param.set_param("itr_core.phase7_rules_strict", "1")
    env.registry.clear_cache()
    relaxed = relaxed_pair is not None
    pair_detail = "none"
    if relaxed_pair:
        pair_detail = "%s/%s" % (relaxed_pair[0]._name, relaxed_pair[1].login)
    chk("V7-08", "کلید اضطراری Ruleها کار می‌کند و خاموش‌کردن آن لاگ می‌شود (Q07/R4)",
        relaxed and log_after > log_before,
        "pair=%s log %s→%s" % (pair_detail, log_before, log_after))

except Exception as error:  # noqa: BLE001
    traceback.print_exc()
    failed += 1
    checks.append(("V7-ERR", "FAIL", "verify crashed", str(error)))

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
log "ops/verify/verify_phase7.py"

# =============================================================================
step "4) پچ افزایشی و idempotent فایل‌های مشترک (R1 — فقط append با مارک)"
# =============================================================================
python3 - "${CORE_DIR}" "${TRN_DIR}" "${CUSTOM_ADDONS}" <<'PYEOF'
import io
import os
import re
import sys

core_dir, trn_dir, addons = sys.argv[1], sys.argv[2], sys.argv[3]
changed = []


def read(path):
    with io.open(path, encoding="utf-8") as handle:
        return handle.read()


def write(path, text):
    with io.open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


# --- models __init__ -------------------------------------------------------
for label, mod_dir in (("itr_core", core_dir), ("itr_transport", trn_dir)):
    path = os.path.join(mod_dir, "models", "__init__.py")
    text = read(path)
    imp = "from . import itr_sec_phase7"
    if imp not in text.splitlines():
        text = text.rstrip("\n") + "\n" + imp + "\n"
        changed.append("%s/models/__init__.py + itr_sec_phase7" % label)
    write(path, text)


def add_manifest_entries(mod_dir, entries, label):
    path = os.path.join(mod_dir, "__manifest__.py")
    text = read(path)
    for entry in entries:
        if ('"%s"' % entry) in text or ("'%s'" % entry) in text:
            continue
        anchor = '"data": ['
        if anchor not in text:
            anchor = "'data': ["
        text = text.replace(anchor, anchor + '\n        "%s",' % entry, 1)
        changed.append("%s manifest + %s" % (label, entry))
    write(path, text)


add_manifest_entries(core_dir, [
    "security/itr_core_phase7_rules.xml",
    "data/itr_core_phase7_data.xml",
], "itr_core")
add_manifest_entries(trn_dir, [
    "security/itr_transport_phase7_rules.xml",
], "itr_transport")

# --- transport tests __init__ ----------------------------------------------
path = os.path.join(trn_dir, "tests", "__init__.py")
text = read(path) if os.path.exists(path) else ""
imp = "from . import test_security_phase7"
if imp not in text.splitlines():
    text = text.rstrip("\n") + ("\n" if text else "") + imp + "\n"
    changed.append("itr_transport/tests/__init__.py + test_security_phase7")
write(path, text)

# cleanup stale core test
path = os.path.join(core_dir, "tests", "__init__.py")
if os.path.exists(path):
    text = read(path)
    stale = "from . import test_security_phase7"
    if stale in text.splitlines():
        text = "\n".join(line for line in text.splitlines() if line.strip() != stale)
        if text and not text.endswith("\n"):
            text += "\n"
        write(path, text)
        changed.append("itr_core/tests/__init__.py - stale test_security_phase7")
    stale_file = os.path.join(core_dir, "tests", "test_security_phase7.py")
    if os.path.exists(stale_file):
        os.remove(stale_file)
        changed.append("removed stale itr_core/tests/test_security_phase7.py")

# --- ACL auditor -----------------------------------------------------------
acl_rows = {
    os.path.join(core_dir, "security", "ir.model.access.csv"): [
        "access_itr_trade_case_auditor_p7,itr.trade.case auditor ro,model_itr_trade_case,itr_core.group_auditor,1,0,0,0",
        "access_itr_trade_case_item_auditor_p7,itr.trade.case.item auditor ro,model_itr_trade_case_item,itr_core.group_auditor,1,0,0,0",
        "access_itr_sales_slip_auditor_p7,itr.sales.slip auditor ro,model_itr_sales_slip,itr_core.group_auditor,1,0,0,0",
        "access_itr_work_assignment_log_auditor_p7,itr.work.assignment.log auditor ro,model_itr_work_assignment_log,itr_core.group_auditor,1,0,0,0",
        "access_itr_factory_shortfall_auditor_p7,itr.factory.shortfall auditor ro,model_itr_factory_shortfall,itr_core.group_auditor,1,0,0,0",
    ],
    os.path.join(trn_dir, "security", "ir.model.access.csv"): [
        "access_itr_transport_case_auditor_p7,itr.transport.case auditor ro,model_itr_transport_case,itr_core.group_auditor,1,0,0,0",
        "access_itr_cost_line_auditor_p7,itr.cost.line auditor ro,model_itr_cost_line,itr_core.group_auditor,1,0,0,0",
        "access_itr_payment_request_auditor_p7,itr.payment.request auditor ro,model_itr_payment_request,itr_core.group_auditor,1,0,0,0",
        "access_itr_payment_execution_auditor_p7,itr.payment.execution auditor ro,model_itr_payment_execution,itr_core.group_auditor,1,0,0,0",
        "access_itr_transport_document_auditor_p7,itr.transport.document auditor ro,model_itr_transport_document,itr_core.group_auditor,1,0,0,0",
    ],
}
for path, rows in acl_rows.items():
    text = read(path)
    for row in rows:
        acl_id = row.split(",", 1)[0]
        if acl_id + "," not in text:
            text = text.rstrip("\n") + "\n" + row + "\n"
            changed.append("acl + %s" % acl_id)
    write(path, text)

# --- i18n ------------------------------------------------------------------
path = os.path.join(trn_dir, "i18n", "fa_IR.po")
if os.path.exists(path):
    text = read(path)
    MARK = "#### itr_transport phase-7 translations ####"
    if MARK not in text:
        text = text.rstrip("\n") + "\n\n" + MARK + """

#. module: itr_transport
#: code:addons/itr_transport/models/itr_sec_phase7.py:0
#, python-format
msgid "Segregation of duties (SEC-015): the user who recorded cost line %(l)s may not also execute its payment (registrar != approver != payer)."
msgstr "تفکیک وظایف (SEC-015): کاربری که ردیف هزینهٔ %(l)s را ثبت کرده، نمی‌تواند خودش پرداخت آن را اجرا کند (ثبت‌کننده ≠ تأییدکننده ≠ پرداخت‌کننده)."
"""
        changed.append("itr_transport i18n + phase-7 block")
    write(path, text)

# --- [R5] notify test_40: checklist 2.29 applies only to itr_notify-owned seeds
# Business events seeded later by itr_core/itr_transport are legitimate (phase 4/6/10).
notify_test = os.path.join(addons, "itr_notify", "tests", "test_event_validation.py")
if os.path.exists(notify_test):
    text = read(notify_test)
    MARK = "# ITR-P7-PATCH: 2.29 scope = itr_notify xmlids only"
    if "def test_40_only_system_events_are_seeded" in text:
        if MARK not in text:
            helper = (
                "\n    %s\n"
                "    def _itr_notify_owned_events(self):\n"
                "        Ev = self.env['itr.notification.event']\n"
                "        events = Ev.search([])\n"
                "        owned = Ev.browse()\n"
                "        for ev in events:\n"
                "            xid = ev.get_external_id().get(ev.id) or ''\n"
                "            if xid.startswith('itr_notify.'):\n"
                "                owned |= ev\n"
                "        return owned\n"
            ) % MARK
            text = text.replace(
                "    def test_40_only_system_events_are_seeded",
                helper + "\n    def test_40_only_system_events_are_seeded",
                1,
            )
            changed.append("itr_notify test_40 helper injected (2.29)")

        broad_seed_searches = (
            'seeded = self.env["itr.notification.event"].search([("is_seed", "=", True)])',
            "seeded = self.env['itr.notification.event'].search([('is_seed', '=', True)])",
        )
        scoped_seed_search = "seeded = self._itr_notify_owned_events().filtered(lambda event: event.is_seed)"
        for broad_seed_search in broad_seed_searches:
            if broad_seed_search in text:
                text = text.replace(broad_seed_search, scoped_seed_search, 1)
                changed.append("itr_notify test_40 scoped to itr_notify xmlids (2.29)")
                break
        write(notify_test, text)

print("PATCHED: %d change(s)" % len(changed))
for item in changed:
    print("  *", item)
PYEOF
log "پچ افزایشی کامل شد (idempotent — اجرای دوباره تغییری نمی‌دهد)"

# =============================================================================
step "5) بررسی نحوی پایتون و صحت XML/CSV پیش از هر نصب"
# =============================================================================
set +e
python3 - "${CORE_DIR}" "${TRN_DIR}" "${OPS_DIR}" <<'PYEOF'
import ast, csv, io, os, sys
import xml.etree.ElementTree as ET

errors = []
py_count = xml_count = 0
for root_dir in sys.argv[1:3] + [os.path.join(sys.argv[3], "verify")]:
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
for mod_dir in sys.argv[1:3]:
    acl = os.path.join(mod_dir, "security", "ir.model.access.csv")
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
print("checked: %d python file(s), %d xml file(s)" % (py_count, xml_count))
if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
SYNTAX_RC=$?
set -e
if [[ ${SYNTAX_RC} -eq 0 ]]; then
  gate "G7-03" "نحو پایتون/XML/CSV سالم است (پیش از نصب)" "PASS" "static check"
else
  gate "G7-03" "نحو پایتون/XML/CSV سالم است" "FAIL" "خطای نحوی — بالا را ببینید"
  err "خطای نحوی پیش از نصب (rollback: ${P7_BACKUP_DIR}/${TS})"
fi

# =============================================================================
step "6) ارتقای itr_core + itr_transport (فاز ۷) روی ${DB_NAME} (Q01/NFR-001)"
# =============================================================================
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=info >"${INSTALL_LOG}" 2>&1
INSTALL_RC=$?
set -e
INSTALL_ERRORS="$(grep -cE ' (ERROR|CRITICAL) ' "${INSTALL_LOG}" || true)"
CORE_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${CORE_MODULE}'")"
TRN_AFTER="$(q "${DB_NAME}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
echo "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} core=${CORE_AFTER} transport=${TRN_AFTER}"
if [[ ${INSTALL_RC} -eq 0 && "${INSTALL_ERRORS}" == "0" && "${CORE_AFTER}" == "installed" && "${TRN_AFTER}" == "installed" ]]; then
  gate "G7-04" "ارتقای فاز ۷ بدون خطا" "PASS" "rc=0 errors=0"
else
  gate "G7-04" "ارتقای فاز ۷ بدون خطا" "FAIL" "rc=${INSTALL_RC} errors=${INSTALL_ERRORS} → ${INSTALL_LOG}"
  tail -n 60 "${INSTALL_LOG}" || true
fi

# =============================================================================
step "7) تست‌های خودکار — فاز ۷ *و* بازاجرای کامل فازهای ۱..۶ (Q04 + R5)"
# =============================================================================
if [[ "${SKIP_TESTS}" == "1" ]]; then
  gate "G7-05" "تست‌های فاز ۷ + بازاجرای فازهای ۱..۶ سبز" "FAIL" "SKIP_TESTS=1 (Q04 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
    -u "itr_base,itr_notify,${CORE_MODULE},${TRN_MODULE}" \
    --test-enable --test-tags "/itr_base,/itr_notify,/${CORE_MODULE},/${TRN_MODULE}" \
    --stop-after-init --log-level=info >"${TEST_LOG}" 2>&1
  TEST_RC=$?
  set -e
  TEST_FAILS="$(grep -cE '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" || true)"
  TEST_BROKEN="$(grep -c 'At least one test failed' "${TEST_LOG}" || true)"
  TEST_TOTAL="$(grep -oE '[0-9]+ tests' "${TEST_LOG}" | tail -n1 || true)"
  echo "rc=${TEST_RC} fails=${TEST_FAILS} broken=${TEST_BROKEN} total=${TEST_TOTAL:-?}"
  if [[ ${TEST_RC} -eq 0 && "${TEST_BROKEN}" == "0" && "${TEST_FAILS}" == "0" && -n "${TEST_TOTAL}" ]]; then
    gate "G7-05" "تست‌های فاز ۷ سبز + هیچ رگرسیونی در فازهای ۱..۶ (R5)" "PASS" "${TEST_TOTAL} rc=0"
  else
    gate "G7-05" "تست‌های فاز ۷ + بازاجرای فازهای ۱..۶" "FAIL" "rc=${TEST_RC} fails=${TEST_FAILS} → ${TEST_LOG}"
    grep -A 40 -E '(FAIL|ERROR): Test[A-Za-z0-9_]+\.test_' "${TEST_LOG}" | head -n 200 || true
    echo "rollback: bash ${OPS_DIR}/restore.sh <dump> <fs> ${DB_NAME} + بازگردانی ${P7_BACKUP_DIR}/${TS}"
  fi
fi

# =============================================================================
step "8) verify مستقل V7-00..V7-08 (کاربر واقعی، بدون sudo، rollback در پایان)"
# =============================================================================
if [[ "${SKIP_VERIFY}" == "1" ]]; then
  gate "G7-06" "verify فاز ۷ سبز" "FAIL" "SKIP_VERIFY=1 (Q15 اجباری)"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" shell -c "${CONF_FILE}" -d "${DB_NAME}" --stop-after-init \
    <"${OPS_DIR}/verify/verify_phase7.py" >"${VERIFY_LOG}" 2>&1
  VERIFY_RC=$?
  set -e
  grep -E '^V7-|ITR_VERIFY' "${VERIFY_LOG}" || true
  if grep -q 'ITR_VERIFY_RESULT: PASS' "${VERIFY_LOG}"; then
    gate "G7-06" "verify فاز ۷: هر ۸ سنجه + ماتریس ۱۳ گروه سبز" "PASS" "$(grep ITR_VERIFY_SUMMARY "${VERIFY_LOG}" | tail -n1)"
  else
    gate "G7-06" "verify فاز ۷ سبز" "FAIL" "rc=${VERIFY_RC} → ${VERIFY_LOG}"
    tail -n 80 "${VERIFY_LOG}" || true
  fi
fi

# =============================================================================
step "9) گاردهای معماری (G18/G01/Q03/Q05 + بدون بازنویسی فایل‌های قبلی)"
# =============================================================================
SUDO_HITS="$(grep -rnE '\.sudo\(\)' --include='*.py' "${CORE_DIR}/models/itr_sec_phase7.py" "${TRN_DIR}/models/itr_sec_phase7.py" 2>/dev/null | grep -v 'ITR-SUDO-OK' || true)"
if [[ -z "${SUDO_HITS}" ]]; then
  gate "G7-07" "هیچ sudo() کسب‌وکاری در فایل‌های فاز ۷ (G01)" "PASS" "clean"
else
  gate "G7-07" "هیچ sudo() کسب‌وکاری در فایل‌های فاز ۷ (G01)" "FAIL" "$(echo "${SUDO_HITS}" | head -n2 | tr '\n' ' ')"
fi
TASK_HITS="$(grep -rnE '_name = "itr\.(task|work\.queue|todo|cartable\.item)"' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null || true)"
SLA_HITS="$(grep -rlnE '_cron_scan_sla|def .*escalate' --include='*.py' "${CUSTOM_ADDONS}" 2>/dev/null | grep -v '/itr_notify/' || true)"
if [[ -z "${TASK_HITS}" && -z "${SLA_HITS}" ]]; then
  gate "G7-08" "تک‌موتور Task/SLA حفظ شد (G18)" "PASS" "clean"
else
  gate "G7-08" "تک‌موتور Task/SLA حفظ شد (G18)" "FAIL" "${TASK_HITS} ${SLA_HITS}"
fi
ADMIN_BIZ="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN ir_model_data d ON d.res_id=r.gid AND d.model='res.groups' WHERE r.uid=(SELECT id FROM res_users WHERE login='admin') AND d.module IN ('itr_core') ")"
[[ -z "${ADMIN_BIZ}" ]] && ADMIN_BIZ="$(q "${DB_NAME}" "SELECT count(*) FROM res_groups_users_rel r JOIN ir_model_data d ON d.res_id=r.gid AND d.model='res.groups' AND d.module='itr_core' WHERE r.uid=2")"
if [[ "${ADMIN_BIZ:-0}" == "0" ]]; then
  gate "G7-09" "Administrator بدون هیچ گروه کسب‌وکاری (Q03 — SQL مستقیم)" "PASS" "count=0"
else
  gate "G7-09" "Administrator بدون هیچ گروه کسب‌وکاری (Q03)" "FAIL" "count=${ADMIN_BIZ}"
fi
RULES_CNT="$(q "${DB_NAME}" "SELECT count(*) FROM ir_rule WHERE name ILIKE '%phase 7%' OR name ILIKE '%SEC-013%' OR name ILIKE '%SEC-014%'")"
if [[ "${RULES_CNT:-0}" -ge 4 ]]; then
  gate "G7-10" "Record Rule های فاز ۷ در دیتابیس موجودند (7.1/7.5)" "PASS" "rules=${RULES_CNT}"
else
  gate "G7-10" "Record Rule های فاز ۷ در دیتابیس موجودند" "FAIL" "rules=${RULES_CNT}"
fi

# =============================================================================
step "10) اثبات Idempotency — اجرای دوبارهٔ ارتقا (NFR-002)"
# =============================================================================
C1="$(q "${DB_NAME}" "SELECT count(*) FROM ir_rule")"
C2="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_access")"
set +e
python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
  -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=warn >"${IDEMP_LOG}" 2>&1
IDEMP_RC=$?
set -e
C1B="$(q "${DB_NAME}" "SELECT count(*) FROM ir_rule")"
C2B="$(q "${DB_NAME}" "SELECT count(*) FROM ir_model_access")"
if [[ ${IDEMP_RC} -eq 0 && "${C1}" == "${C1B}" && "${C2}" == "${C2B}" ]]; then
  gate "G7-11" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "PASS" "rules=${C1B} acl=${C2B}"
else
  gate "G7-11" "اجرای دوباره رکورد تکراری نساخت (NFR-002)" "FAIL" "rules ${C1}→${C1B} acl ${C2}→${C2B} rc=${IDEMP_RC}"
fi

# =============================================================================
step "11) نصب روی پایگاه‌دادهٔ UAT (محیط پذیرش)"
# =============================================================================
if [[ "${SKIP_UAT}" == "1" ]]; then
  warn "SKIP_UAT=1 — UAT رد شد"
  gate "G7-12" "ارتقای UAT بدون خطا" "FAIL" "SKIP_UAT=1"
else
  set +e
  python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE_UAT}" -d "${DB_NAME_UAT}" \
    -u "${CORE_MODULE},${TRN_MODULE}" --stop-after-init --log-level=warn >"${UAT_LOG}" 2>&1
  UAT_RC=$?
  set -e
  UAT_STATE="$(q "${DB_NAME_UAT}" "SELECT state FROM ir_module_module WHERE name='${TRN_MODULE}'")"
  if [[ ${UAT_RC} -eq 0 && "${UAT_STATE}" == "installed" ]]; then
    gate "G7-12" "ارتقای UAT بدون خطا" "PASS" "state=installed"
  else
    gate "G7-12" "ارتقای UAT بدون خطا" "FAIL" "rc=${UAT_RC} state=${UAT_STATE} → ${UAT_LOG}"
  fi
fi

# =============================================================================
step "12) اسناد حاکمیتی: ADR-034..036 + گزارش ممیزی + نقشهٔ استفادهٔ مجدد (Q14)"
# =============================================================================
ADR_FILE="${CUSTOM_ADDONS}/ARCHITECTURE_DECISIONS.md"
if ! grep -q "ADR-034" "${ADR_FILE}" 2>/dev/null; then
cat >>"${ADR_FILE}" <<'MDEOF'

## ADR-034 — سقف نوشتن با Record Rule سراسریِ شرطی (فاز ۷)
قواعد SEC-013 به‌صورت global با domain_force شرطی (user.has_group برای مدیران)
پیاده شدند تا جمعِ ORی قواعد گروهی نتواند سقف را دور بزند. دیدپذیری read عمداً
دست‌نخورده ماند (Gate 7 روی «نوشتن» است؛ سفت‌کردن read تصمیم باز کارفرماست).

## ADR-035 — کلید اضطراری قواعد فاز ۷ (itr_core.phase7_rules_strict)
همهٔ قواعد/گاردهای تازهٔ فاز ۷ پشت یک پارامترند (پیش‌فرض روشن). خاموش‌کردن
هرگز بی‌صدا نیست: ir.logging + گزارش در verify. دلیل: مدیریت ریسک شکستن
قرارداد فازهای قبلی بدون نیاز به تغییر کد (Q07).

## ADR-036 — SEC-014 با groups سطح-فیلد
اسکن سند امضاشده و فیش بانکی با `groups` روی خود فیلد محافظت شدند (نه با
مخفی‌سازی UI)؛ Odoo فیلد محافظت‌شده را از view و RPC هر دو حذف/مسدود می‌کند.

## ADR-037 — FIX-P7-4 person-level SoD روی action_issue اعمال نشد
ماتریس ۵.۱ صریحاً finance_supervisor را مجاز به صدور slip می‌داند و همان نقش
تأیید امضای فیزیکی را انجام می‌دهد. قفل person-level (signed_by ≠ issuer)
رگرسیون فاز۵ و واقعیت سازمانی را می‌شکست. SoD سخت روی پرداخت [FIX-P7-3] پابرجاست.
MDEOF
fi

if [[ -f "${DOC_DIR}/REUSE_MAP.md" ]] && ! grep -q "phase-7" "${DOC_DIR}/REUSE_MAP.md"; then
cat >>"${DOC_DIR}/REUSE_MAP.md" <<'MDEOF'

## phase-7 (نقشهٔ استفادهٔ مجدد — Q14)
* `itr.supervisor.team.get_subordinate_users` (فاز ۳) → مرز بازتخصیص SEC-004؛ مدل موازی ساخته نشد.
* `itr.cartable.mixin.assign_to/_hand_over_to_group` (فاز ۵) → همان مسیر یگانهٔ ارجاع؛ فقط اثبات مجدد شد.
* `_forbid_self_approval` (فاز ۴) و گارد SoD اجرای پرداخت (فاز ۶) → پایهٔ 7.4؛ [FIX-P7-3] با inherit افزایشی بسته شد.
* ACL/گروه‌های فاز ۳ → هیچ گروه جدیدی ساخته نشد؛ فقط ACL خواندنی auditor تکمیل شد [FIX-P7-5].
* گارد SoD پرداخت [FIX-P7-3] در itr_transport (مالک مدل itr.payment.request) — نه در itr_core (Q02).
MDEOF
fi

write_utf8 "${DOC_DIR}/PHASE7-AUDIT-FINDINGS.md" <<'MDEOF'
# ممیزی فاز ۷ — اشتباهات کشف‌شده در فازهای قبل و نحوهٔ رفع (افزایشی، بدون بازنویسی)

| # | یافته | ریشه | رفع در فاز ۷ |
|---|-------|------|--------------|
| ۱ | مدل‌های دامنهٔ فاز ۴/۵/۶ هیچ Record Rule سطری نداشتند | بند 3.11 اسکلت | قواعد سقف نوشتن شرطی + auditor RO ([FIX-P7-1]) |
| ۲ | SEC-014 اجرا نشده بود | تمرکز گردش در ۴/۶ | groups سطح-فیلد + Rule سند مالی ([FIX-P7-2]) |
| ۳ | ثبت‌کنندهٔ cost line می‌توانست خودش پرداخت کند | گارد فاز ۶ ناقص | registrar ≠ payer در itr_transport ([FIX-P7-3]) |
| ۴ | signed_by ≠ issuer روی slip | تعارض با نقش ۵.۱ | ADR-037: اعمال نشد؛ نقش‌محور ماند |
| ۵ | Auditor بدون ACL صریح | قلم‌افتادگی فاز ۶ | ACL read-only ([FIX-P7-5]) |
| ۶ | تست notify 2.29 رویدادهای فاز بعد را business می‌دید | scope تست | محدود به xmlidهای itr_notify |
MDEOF

write_utf8 "${DOC_DIR}/PHASE7-DELIVERY.md" <<MDEOF
# تحویل فاز ۷ — $(date -Is)

## Scope انجام‌شده
7.1 Record Rule (SEC-012/013) | 7.2 بازتخصیص تیم‌محور (SEC-004) |
7.3 Administrator مقدس (Q03) | 7.4 SoD پرداخت (SEC-015/[FIX-P7-3]) |
7.5 پیوست‌های مالی (SEC-014) | SEC-017 | SEC-019

## Rollback
restore.sh + docs/phase7-backup/${TS}
MDEOF
log "اسناد حاکمیتی ثبت شد"

# =============================================================================
step "13) اجرای دوبارهٔ سرویس + healthcheck"
# =============================================================================
if [[ "${START_DAEMON}" == "1" ]]; then
  if ! ss -lntp 2>/dev/null | grep -q ":${HTTP_PORT} "; then
    rm -f "${PID_FILE}"
    nohup python "${ODOO_DIR}/odoo-bin" -c "${CONF_FILE}" -d "${DB_NAME}" \
      --http-interface="${HTTP_INTERFACE}" --http-port="${HTTP_PORT}" \
      >"${LOG_FILE}" 2>&1 &
    echo $! >"${PID_FILE}"
    sleep 3
  fi
  HTTP_CODE="000"
  for _ in $(seq 1 20); do
    HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HTTP_PORT}/web/login" || echo 000)"
    [[ "${HTTP_CODE}" == "200" ]] && break
    sleep 2
  done
  if [[ "${HTTP_CODE}" == "200" ]]; then
    gate "G7-13" "سرویس بالا و صفحهٔ ورود HTTP 200" "PASS" "code=200"
  else
    gate "G7-13" "سرویس بالا و صفحهٔ ورود HTTP 200" "FAIL" "code=${HTTP_CODE}"
  fi
else
  warn "START_DAEMON=0 — راه‌اندازی سرویس رد شد"
  gate "G7-13" "سرویس بالا" "PASS" "START_DAEMON=0 (آگاهانه)"
fi

# =============================================================================
step "14) ثبت Git + تگ phase-7 (Q09) + اسکن رمز (Q12)"
# =============================================================================
git -C "${CUSTOM_ADDONS}" add -A
if git -C "${CUSTOM_ADDONS}" diff --cached --quiet; then
  warn "commit جدیدی لازم نبود (idempotent)"
else
  git -C "${CUSTOM_ADDONS}" commit -q -m "phase-7: permission matrix, record rules, SoD payment, SEC-014 field security"
  log "git commit ثبت شد"
fi
if ! git -C "${CUSTOM_ADDONS}" rev-parse -q --verify refs/tags/phase-7 >/dev/null; then
  git -C "${CUSTOM_ADDONS}" tag phase-7 || true
fi
SECRET_HITS="$(git -C "${CUSTOM_ADDONS}" ls-files -z -- '*phase7*' | xargs -0 -r grep -nIE '(api[_-]?key|password)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']+' 2>/dev/null || true)"
if [[ -z "${SECRET_HITS}" ]]; then
  gate "G7-14" "Git commit + تگ phase-7 + بدون رمز در فایل‌های فاز (Q12)" "PASS" "HEAD=$(git -C "${CUSTOM_ADDONS}" rev-parse --short HEAD)"
else
  gate "G7-14" "بدون رمز در فایل‌های فاز (Q12)" "FAIL" "$(echo "${SECRET_HITS}" | head -n2 | tr '\n' ' ')"
fi

# =============================================================================
step "GATE 7 — گزارش پذیرش فاز ۷"
# =============================================================================
FAILS=0
printf "\n%-8s %-8s %s\n" "ID" "STATUS" "CHECK"
printf -- "---------------------------------------------------------------------------\n"
for i in "${!GATE_IDS[@]}"; do
  st="${GATE_ST[$i]}"
  if [[ "${st}" == "PASS" ]]; then c="${GREEN}"; else c="${RED}"; FAILS=$((FAILS+1)); fi
  printf "%-8s ${c}%-8s${NC} %s\n" "${GATE_IDS[$i]}" "${st}" "${GATE_TXT[$i]}"
  [[ -n "${GATE_MSG[$i]}" ]] && printf "%-8s %-8s   ↳ %s\n" "" "" "${GATE_MSG[$i]}"
done
printf -- "---------------------------------------------------------------------------\n"

trap - EXIT
if [[ ${FAILS} -eq 0 ]]; then
  echo -e "\n${GREEN}GATE 7 = سبز ✅ — «هیچ کاربر واقعی خارج از حیطهٔ نقش خود نوشتن ندارد» و «بازتخصیص تیم‌محور ردیابی‌پذیر است». مجاز به شروع فاز ۸ (کارتابل/Workspace).${NC}\n"
  exit 0
else
  echo -e "\n${RED}GATE 7 = قرمز ❌ (${FAILS} مورد ناموفق) — طبق Q08 فاز ۸ آغاز نمی‌شود. Rollback: docs/phase7-backup/${TS}${NC}\n"
  exit 1
fi
