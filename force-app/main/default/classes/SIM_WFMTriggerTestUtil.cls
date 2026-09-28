/**
 * @description Shared test-only helpers for the WFM Contract/Job Role trigger tests
 *              (SIM_ProActiveContractTriggerTest, SIM_JobRoleTriggerTest). The
 *              Contract_Sync_Fields / Job_Role_Sync_Fields field sets that drive
 *              SIM_ProActiveContract_Helper and SIM_JobRole_Helper are configured
 *              directly in the org and not tracked in source, so their field
 *              membership is unknown at authoring time. These helpers inspect
 *              whichever field set is actually configured and pick a field they
 *              can safely set a new value on, so the sync/validation trigger
 *              paths can be exercised without hardcoding a specific field.
 * @author      Lakmal Rajapakse
 * @group       WFM Contracts
 * @last modified on  : 2026-08-24
**/
@isTest
public class SIM_WFMTriggerTestUtil {

    public class FieldChoice {
        public String fieldPath;
        public Object value;
    }

    /**
     * Finds the first field in the given field set (skipping anything in
     * excludedFieldsLower) that is updateable and for which an alternate,
     * non-null value can be generated. Returns null if the field set does not
     * exist, is empty, or has no field this helper knows how to populate.
     */
    public static FieldChoice pickAlternateFieldValue(
        Schema.DescribeSObjectResult sObjType,
        String fieldSetDeveloperName,
        Set<String> excludedFieldsLower,
        Id recId
    ) {
        Schema.FieldSet fs = sObjType.fieldSets.getMap().get(fieldSetDeveloperName);
        if (fs == null) return null;

        List<String> fieldNames = new List<String>();
        for (Schema.FieldSetMember fsm : fs.getFields()) {
            fieldNames.add(fsm.getFieldPath());
        }

        SObject rec = recId == null ? null : Database.query('SELECT ' + String.join(fieldNames, ',') + ' FROM ' + sObjType.getName() + ' WHERE Id = :recId')[0];

        for (Schema.FieldSetMember fsm : fs.getFields()) {
            String fieldPath = fsm.getFieldPath();
            if (excludedFieldsLower != null && excludedFieldsLower.contains(fieldPath.toLowerCase())) continue;

            Schema.SObjectField sf = sObjType.fields.getMap().get(fieldPath);
            if (sf == null) continue;

            Schema.DescribeFieldResult dfr = sf.getDescribe();
            if (!dfr.isUpdateable()) continue;

            Object alt = buildAlternateValue(dfr, ((rec == null) ? null : rec.get(fieldPath)));
            if (alt != null) {
                FieldChoice choice = new FieldChoice();
                choice.fieldPath = fieldPath;
                choice.value = alt;
                return choice;
            }
        }
        return null;
    }

    /** Builds a value of the correct type for dfr that differs from currentValue, or null if the type isn't supported. */
    public static Object buildAlternateValue(Schema.DescribeFieldResult dfr, Object currentValue) {
        Schema.DisplayType type = dfr.getType();

        if (type == Schema.DisplayType.STRING || type == Schema.DisplayType.TEXTAREA
            || type == Schema.DisplayType.PHONE || type == Schema.DisplayType.URL
            || type == Schema.DisplayType.EMAIL) {
            String cur = currentValue == null ? null : String.valueOf(currentValue);
            return (cur == 'Sync Test Value A') ? 'Sync Test Value B' : 'Sync Test Value A';
        }
        if (type == Schema.DisplayType.BOOLEAN) {
            Boolean cur = currentValue == null ? false : (Boolean) currentValue;
            return !cur;
        }
        if (type == Schema.DisplayType.DOUBLE || type == Schema.DisplayType.CURRENCY || type == Schema.DisplayType.PERCENT) {
            Decimal cur = currentValue == null ? 0 : (Decimal) currentValue;
            return cur + 100;
        }
        if (type == Schema.DisplayType.INTEGER) {
            Integer cur = currentValue == null ? 0 : (Integer) currentValue;
            return cur + 1;
        }
        if (type == Schema.DisplayType.DATE) {
            Date cur = currentValue == null ? null : (Date) currentValue;
            return cur == null ? Date.today() : cur.addDays(1);
        }
        if (type == Schema.DisplayType.DATETIME) {
            Datetime cur = currentValue == null ? null : (Datetime) currentValue;
            return cur == null ? Datetime.now() : cur.addDays(1);
        }
        if (type == Schema.DisplayType.PICKLIST) {
            String curStr = currentValue == null ? null : String.valueOf(currentValue);
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive() && pe.getValue() != curStr) {
                    return pe.getValue();
                }
            }
            return null;
        }
        return null; // unsupported type (reference, multipicklist, etc.)
    }
}