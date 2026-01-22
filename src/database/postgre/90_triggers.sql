-- Aplicando Trigger
CREATE TRIGGER trg_audit_policies
AFTER INSERT OR UPDATE OR DELETE ON core.policies
FOR EACH ROW EXECUTE FUNCTION audit.log_changes_trigger();