integer num_notecards;
list notecards;
integer notecard_index;
integer notecard_line;
integer notecard_errors;
integer total_errors;

default
{
    state_entry()
    {
        llSetText("Drop Open Trivia Database Quiz Machine notecards into me to validate them!", <1, 1, 1>, 1);
    }
    
    changed(integer change)
    {
        if (change & CHANGED_INVENTORY)
        {
            num_notecards = llGetInventoryNumber(INVENTORY_NOTECARD);
            
            if (num_notecards > 0)
            {
                integer i;
                for (i = 0; i < num_notecards; ++i)
                {
                    notecards += llGetInventoryName(INVENTORY_NOTECARD, i);
                }
                
                llOwnerSay("Checking notecards...");
                
                total_errors = 0;
                notecard_errors = 0;
                llGetNotecardLine(llList2String(notecards, notecard_index = 0), notecard_line = 0);
            }
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (data == EOF)
        {
            if (notecard_errors == 0)
            {
                llOwnerSay("  [✓] " + llList2String(notecards, notecard_index));
            }
            else
            {
                llOwnerSay("  [x] " + llList2String(notecards, notecard_index));
            }
            
            if (notecard_index < num_notecards - 1)
            {   
                notecard_errors = 0;
                llGetNotecardLine(llList2String(notecards, ++notecard_index), notecard_line = 0);
            }
            else
            {
                if (total_errors == 0)
                {
                    llOwnerSay("[✓] All notecards passed!");
                }
                else
                {
                    llOwnerSay("[x] There are issues with some of these notecards.");
                }
                
                integer i;
                for (i = 0; i < num_notecards; ++i)
                {
                    string name = llGetInventoryName(INVENTORY_NOTECARD, i);
                    
                    if (name != "")
                    {
                        llRemoveInventory(name);
                    }
                }
            }
            
            return;
        }

        list fields = llParseStringKeepNulls(data, ["  "], []);
        
        if (llGetListLength(fields) < 5)
        {
            ++notecard_errors;
            ++total_errors;
            llOwnerSay("ERROR: " + llList2String(notecards, notecard_index) + ": " + (string) notecard_line + ": Too few fields.");
        }
        
        llGetNotecardLine(llList2String(notecards, notecard_index), ++notecard_line);
    }
}
