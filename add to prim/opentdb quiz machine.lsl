/* Open Trivia Database Quiz Machine v3.1.0 */

/** CONFIGURATION **/

/* The name of the configuration notecard in the inventory. */
string config_notecard_name = "opentdb quiz machine config";

/* URL of the Open Trivia Database API */
string opentdb_api = "https://opentdb.com/api.php";

/* URL of the list of categories in the Open Trivia Database API */
string opentdb_api_categories = "https://opentdb.com/api_category.php";

/* The encoding we want the API to use */
string opentdb_api_encoding = "url3986";

/* The delay in seconds before a question is asked after announcing it */
float question_delay = 10;

/* The time in seconds players have to answer a question */
float answer_timeout = 30;

/* The time in seconds before the quiz setup dialogs will timeout */
float setup_timeout = 60;

/* The delay before the quiz starts after announcing it */
float quiz_start_time = 20;

/* The delay before the machine resets after a quiz ends */
float quiz_end_time = 10;

/* The maximum number of questions that can be selected */
integer max_questions = 50;

/* The play mode of the machine:
 *
 * 0: Locked: Only the owner may start a quiz.
 * 1: Pay-to-play: Anyone may pay to start a quiz, but only the owner can start a quiz without paying.
 * 2: Free-to-play: Anyone can start a quiz without paying.
 */
integer play_mode = 1;

/* The color to use for hover text */
vector text_color = <1, 1, 1>;

/* Whether a group is required to participate in quizzes. */
integer require_group = FALSE;

/** END OF CONFIGURATION **/

/* The channel used for dialogs */
integer dialog_channel;

/* Stores the list of categories as JSON objects */
list categories;

/* Stores which category the category choice dialog is on in order to have multiple pages */
integer categories_index;

/* The person who initiated the quiz */
key quiz_starter;

/* The amount the quiz starter paid and how much is leftover */
integer amount_paid;

/* The selected total number of questions */
integer total_questions;

/* The selected category */
string category;

/* The selected difficulty */
string difficulty;

/* The selected payout */
integer payout;

/* The list of questions return by the API as JSON objects */
string question_data;

/* The current question the quiz is on */
integer question_number;

/* The current correct answer for the current question */
string correct_answer;

/* A list of players that have already guessed incorrectly on the current question */
list incorrect_guessers;

/* The number of questions each player has gotten correct */
list scores;

/* The listener ID for some dialogs */
integer listener;

/* Query ID when reading questions from notecards */
key notecard_query;

/* Current line being read in a notecard. */
integer notecard_line;

/* Lines from the current category notecard */
integer notecard_lines;

/* Numbers of lines of questions in randomized order. */
list notecard_questions;

/* Current step the setup process is on:
 * 0: Choose category
 * 1: Choose total questions
 * 2: Choose difficulty
 * 3: Choose payout
 */
integer setup_step;

/* Display a message both overhead and in nearby chat */
announce(string text)
{
    llSetText(text, text_color, 1);
    llSay(0, "\n" + text);
}

/* Display a page of the category choice dialog */
open_category_dialog()
{
    string text = "Choose a category:";
    list buttons = ["CANCEL", "random", "MORE"];
    
    integer i;
    
    for (i = categories_index; i < llGetListLength(categories) && i < categories_index + 9; ++i)
    {
        string json = llList2String(categories, i);
        string id = llJsonGetValue(json, ["id"]);
        string name = llJsonGetValue(json, ["name"]);

        if (id != name)
        {
            text += "\n" + id + ": " + name;
        }
        
        buttons += id;
    }
    
    llDialog(quiz_starter, text, buttons, dialog_channel);
}

open_total_questions_dialog()
{
    string total_questions_text = "How many questions?";
    list total_questions_buttons;
    
    /* If no payment was made, create a standard set of question numbers. */
    if (amount_paid == 0)
    {
        /* If the questions are from a notecard, don't allow selecting more questions than the notecard contains. */
        if (llGetInventoryType(category) == INVENTORY_NOTECARD)
        {
            total_questions_buttons = ["1"];
            integer i;
            for (i = 5; i <= notecard_lines && i <= 50; i += 5)
            {
                total_questions_buttons += (string) i;
            }
        }
        /* If the questions are from the API, just use multiples of 5 up to 50 */
        else
        {
            total_questions_buttons = ["1", "5", "10", "15", "20", "25", "30", "35", "40", "45", "50"];
        }
    }
    /* If someone paid the machine, then create a list of possible numbers of questions based on factors of the amount they paid */
    else
    {
        integer factor;
        integer buttons;
        
        for (factor = amount_paid; factor >= 1 && buttons <= 10; --factor)
        {
            if (amount_paid % factor == 0)
            {
                integer possible_total_questions = amount_paid / factor;
                
                if (possible_total_questions <= max_questions)
                {
                    integer possible_payout = amount_paid / possible_total_questions;
                    total_questions_text += "\n" + (string) possible_total_questions + " = L$" + (string) possible_payout + " per question";
                    total_questions_buttons += (string) possible_total_questions;
                    ++buttons;
                }
            }
        }            
    }
    
    /* Display the possible numbers of questions in a dialog and let the quiz starter choose */
    llDialog(quiz_starter, total_questions_text, ["CANCEL"] + total_questions_buttons, dialog_channel);
}

open_payout_dialog()
{
    llDialog(quiz_starter, "How much is each question worth?", ["CANCEL", "0", "10", "20", "50", "100", "200", "500", "1000", "2000", "5000", "prize"], dialog_channel);
}

/* In the default state, request the necessary permissions from the owner */
default
{
    state_entry()
    {
        llOwnerSay("Free memory: " + (string) llGetFreeMemory());
        
        llSetText("Setting up... (touch to set permissions)", text_color, 1);
        
        /* Get a unique channel number based on the object's key. */
        dialog_channel = 0x80000000 | (integer)("0x"+(string)llGetKey());
                        
        llSetClickAction(CLICK_ACTION_TOUCH);
        
        llRequestPermissions(llGetOwner(), PERMISSION_DEBIT);
    }
    
    on_rez(integer start_param)
    {
        llRequestPermissions(llGetOwner(), PERMISSION_DEBIT);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the owner.");
            return;
        }
        
        llRequestPermissions(llGetOwner(), PERMISSION_DEBIT);
    }
    
    run_time_permissions(integer permissions)
    {
        if (permissions & PERMISSION_DEBIT)
        {
            if (llGetInventoryType(config_notecard_name) == INVENTORY_NOTECARD)
            {
                llSetText("Reading configuration...", text_color, 1);
                notecard_query = llGetNotecardLine(config_notecard_name, notecard_line = 0);
            }
            else
            {
                state ready;
            }
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id != notecard_query)
        {
            return;
        }
        
        if (data == EOF)
        {
            state ready;
        }
        
        if (data != "" && llGetSubString(data, 0, 0) != "#")
        {
            integer pos = llSubStringIndex(data, " = ");
            
            if (pos != -1)
            {
                string name = llGetSubString(data, 0, pos - 1);
                string value = llGetSubString(data, pos + 3, -1);
                
                if (name == "question_delay")
                {
                    question_delay = (float) value;
                }
                else if (name == "answer_timeout")
                {
                    answer_timeout = (float) value;
                }
                else if (name == "setup_timeout")
                {
                    setup_timeout = (float) value;
                }
                else if (name == "quiz_start_time")
                {
                    quiz_start_time = (float) value;
                }
                else if (name == "quiz_end_time")
                {
                    quiz_end_time = (float) value;
                }
                else if (name == "max_questions")
                {
                    max_questions = (integer) value;
                }
                else if (name == "play_mode")
                {
                    play_mode = (integer) value;
                }
                else if (name == "text_color")
                {
                    text_color = (vector) value;
                }
                else if (name == "require_group")
                {
                    require_group = (integer) value;
                }
            }
        }
        
        notecard_query = llGetNotecardLine(config_notecard_name, ++notecard_line);
    }
}

/* The machine is ready to start a quiz */
state ready
{
    state_entry()
    {
        /* Clear previous quiz settings */
        amount_paid = 0;   
        quiz_starter = NULL_KEY;
        categories = [];
        category = "";
        difficulty = "";
        question_data = "";
        correct_answer = "";
        scores = [];
        notecard_lines = 0;
        notecard_questions = [];
                        
        /* Set the buttons that appear in the Pay dialog */
        if (play_mode == 0)
        {
            llSetPayPrice(PAY_HIDE, [PAY_HIDE, PAY_HIDE, PAY_HIDE, PAY_HIDE]);
        }
        else
        {
            llSetPayPrice(PAY_DEFAULT, [10, 50, 100, 500]);
        }
        
        /* Make it so clicking the machine initiates the Pay event */
        if (play_mode == 1)
        {
            llSetClickAction(CLICK_ACTION_PAY);
        }
        else
        {
            llSetClickAction(CLICK_ACTION_TOUCH);
        }
        
        if (play_mode == 0)
        {
            llSetText("", <0, 0, 0>, 0);
        }
        else if (play_mode == 1)
        {
            llSetText("Pay me to start a quiz!", text_color, 1);
        }
        else
        {
            llSetText("Touch or pay me to start a quiz!", text_color, 1);
        }
    }
    
    /* The owner of the machine can start a quiz without paying, and has some additional options.
    
       Additionally, if the machine is set in free-to-play mode, anyone can start a quiz without paying,
       though they do not have access to all the same options as the owner (such as setting the payout amount). */
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher == llGetOwner() || (play_mode == 2 && (!require_group || llSameGroup(toucher))))
        {
            amount_paid = 0;
            quiz_starter = toucher;
            state setup;
        }
        else
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the owner or group.");
        }
    }
    
    /* Begin the quiz setup when someone pays the machine */
    money(key id, integer amount)
    {
        if (require_group && !llSameGroup(id))
        {
            llRegionSayTo(id, 0, "Sorry, that is restricted to the owner or group.");
            llGiveMoney(id, amount);
        }
        else
        {
            amount_paid = amount;
            quiz_starter = id;
            state setup;
        }
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* Perform the setup for a new quiz. */
state setup
{
    state_entry()
    {
        llSetClickAction(CLICK_ACTION_NONE);
        llListen(dialog_channel, "", quiz_starter, "");

        announce(llGetDisplayName(quiz_starter) + " is starting a quiz...");
        llRegionSayTo(quiz_starter, 0, "If you close out of a dialog during setup, touch the quiz machine again to re-open it.");
        
        setup_step = 0;
        llHTTPRequest(opentdb_api_categories, [], "");
        llSetTimerEvent(setup_timeout);
    }

    /* Re-display the dialog if the machine is touched, in case it is accidentally closed */
    touch_end(integer detected)
    {
        if (llDetectedKey(0) != quiz_starter) return;
        
        if (setup_step == 0)
        {
            llHTTPRequest(opentdb_api_categories, [], "");
        }
        else if (setup_step == 1)
        {
            open_total_questions_dialog();
        }
        else if (setup_step == 2)
        {
            llDialog(quiz_starter, "Choose a difficulty:", ["easy", "medium", "hard", "random", "CANCEL"], dialog_channel);
        }
        else if (setup_step == 3)
        {
             open_payout_dialog();
        }
        
        llSetTimerEvent(setup_timeout);
    }
    
    http_response(key request_id, integer status, list metadata, string body)
    {
        categories = llJson2List(llJsonGetValue(body, ["trivia_categories"]));
        body = "";
        
        if (llGetListLength(categories) < 1)
        {
            llSay(0, "An error occurred fetching the categories.");
            state cancel_quiz;
        }
        
        integer num_notecards = llGetInventoryNumber(INVENTORY_NOTECARD);
        if (num_notecards > 0)
        {
            list notecard_categories;
            integer i;
            for (i = 0; i < num_notecards; ++i)
            {
                string name = llGetInventoryName(INVENTORY_NOTECARD, i);
                if (name != config_notecard_name)
                {
                    notecard_categories += llList2Json(JSON_OBJECT, ["id", name, "name", name]);
                }
            }
            categories = notecard_categories + categories;
        }
        
        categories_index = 0;
        open_category_dialog();
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (message == "CANCEL")
        {
            state cancel_quiz;
        }
        
        if (setup_step == 0)
        {
            if (message == "MORE")
            {
                categories_index += 9;
                
                if (categories_index >= llGetListLength(categories))
                {
                    categories_index = 0;
                }
                
                open_category_dialog();
                return;
            }
            
            category = message;
            
            categories = [];
            
            if (llGetInventoryType(category) == INVENTORY_NOTECARD)
            {
                notecard_query = llGetNumberOfNotecardLines(category);
            }
            else
            {
                setup_step = 1;
                open_total_questions_dialog();
            }
        }
        else if (setup_step == 1)
        {
            total_questions = (integer) message;
            
            if (total_questions < 1)
            {
                state cancel_quiz;
            }
    
            if (llGetInventoryType(category) == INVENTORY_NOTECARD && total_questions > notecard_lines)
            {
                llRegionSayTo(quiz_starter, 0, "The notecard for the chosen category does not contain enough questions.");
                state cancel_quiz;
            }
                    
            if (amount_paid > 0)
            {
                payout = amount_paid / total_questions;
                
                if (payout < 1)
                {
                    llRegionSayTo(quiz_starter, 0, "The payout is too small for each question.");
                    
                    state cancel_quiz;
                }
            }
            
            if (llGetInventoryType(category) == INVENTORY_NOTECARD)
            {
                if (amount_paid == 0)
                {
                    if (quiz_starter == llGetOwner())
                    {
                        setup_step = 3;
                        open_payout_dialog();
                    }
                    else
                    {
                        payout = 0;
                        state begin_quiz;
                    }
                }
                else
                {
                    state begin_quiz;
                }
            }
            else
            {
                setup_step = 2;
                llDialog(quiz_starter, "Choose a difficulty:", ["easy", "medium", "hard", "random", "CANCEL"], dialog_channel);
                llSetTimerEvent(setup_timeout);
            }
        }
        else if (setup_step == 2)
        {
            difficulty = message;
            
            if (amount_paid == 0)
            {
                if (quiz_starter == llGetOwner())
                {
                    setup_step = 3;
                    open_payout_dialog();
                }
                else
                {
                    payout = 0;
                    state begin_quiz;
                }
            }
            else
            {
                state begin_quiz;
            }
        }
        else if (setup_step == 3)
        {
            if (message == "prize")
            {    
                integer objects = llGetInventoryNumber(INVENTORY_OBJECT);
                integer prizes;
                integer i;
                
                for (i = 0; i < objects && prizes < total_questions; ++i)
                {
                    string name = llGetInventoryName(INVENTORY_OBJECT, i);
                    integer perms = llGetInventoryPermMask(name, MASK_OWNER);
                    
                    if (perms & PERM_TRANSFER)
                    {
                        if (perms & PERM_COPY)
                        {
                            prizes = total_questions;
                        }
                        else
                        {
                            ++prizes;
                        }
                    }
                    else
                    {
                        llRegionSayTo(quiz_starter, 0, name + " is not transfer and cannot be used as a prize.");
                    }
                }
                
                if (prizes < total_questions)
                {
                    llRegionSayTo(quiz_starter, 0, "There are too few prizes for the total questions. Please add more and try again.");
                    state cancel_quiz;
                }
                
                /* Set payout to be a prize. */
                payout = -1;
            }
            else
            {
                payout = (integer) message;
            }
            
            state begin_quiz;
        }
    }
    
    dataserver(key query_id, string data)
    {
        if (query_id != notecard_query)
        {
            return;
        }

        notecard_lines = (integer) data;
            
        integer i;
        for (i = 0; i < notecard_lines; ++i)
        {
            notecard_questions += i;
        }
        notecard_questions = llListRandomize(notecard_questions, 1);
        
        setup_step = 1;
        open_total_questions_dialog();
    }

    /* Timeout the quiz setup if the quiz starter takes too long */
    timer()
    {
        llSetTimerEvent(0);
        state cancel_quiz;
    }

    state_exit()
    {
        llSetTimerEvent(0);
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* Fetch the questions from the API and start the quiz */
state begin_quiz
{
    state_entry()
    {
        if (payout > 0)
        {
            integer refund = amount_paid - (payout * total_questions);
                
            if (refund > 0)
            {
                llRegionSayTo(quiz_starter, 0, "You will be refunded the leftover L$" + (string) refund + " that you paid.");
                llGiveMoney(quiz_starter, refund);
                amount_paid -= refund;
            }
        }
                
        question_number = 1;
                
        string text = "A quiz of " + (string) total_questions + " questions has started!\n\nTo play, say the letter corresponding to the correct answer in nearby chat.\n\nEach person may only answer once per question!";
        
        /* If payout is set to a prize... */
        if (payout == -1)
        {
            text += "\n\nEach question is worth a mystery prize!";
        }
        /* If payout is an amount of money... */
        else if (payout > 0)
        {
            text += "\n\nEach question is worth L$" + (string) payout + "!";
        }
        
        llPlaySound("begin", 1);
        
        announce(text);
                
        llSetTimerEvent(quiz_start_time);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != quiz_starter && toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the quiz runner.");
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, "Cancel the quiz?", ["YES", "NO"], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        llListenRemove(listener);
        
        if (message == "YES")
        {
            state cancel_quiz;
        }
    }
    
    timer()
    {
        llSetTimerEvent(0);
        
        scores = [];
        
        state ask_question;
    }

    state_exit()
    {
        llSetTimerEvent(0);
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* Display the question to the players */
state ask_question
{
    state_entry()
    {
        llSetText("Fetching question...", text_color, 1);

        if (llGetInventoryType(category) == INVENTORY_NOTECARD)
        {
            notecard_query = llGetNotecardLine(category, llList2Integer(notecard_questions, question_number - 1));
        }
        else
        {
            string url = opentdb_api + "?encode=" + opentdb_api_encoding + "&amount=1";
            
            if (category != "random")
            {
                url += "&category=" + category;
            }
            
            if (difficulty != "random")
            {
                url += "&difficulty=" + difficulty;
            }
            
            llHTTPRequest(url, [], "");
        }
    }
    
    http_response(key request_id, integer status, list metadata, string body)
    {        
        question_data = llJsonGetValue(body, ["results", 0]);
        body = "";
        
        if (question_data == JSON_INVALID)
        {
            llSay(0, "An error occurred while fetching the question.");
            state cancel_quiz;
        }
        
        if (question_number == 1)
        {
            announce("Here comes the first question...");
        }
        else if (question_number == total_questions)
        {
            announce("Here comes the last question...");
        }
        else
        {
            announce("Here comes the next question...");
        }
                        
        llSetTimerEvent(question_delay);
    }
     
    dataserver(key query_id, string data)
    {
        if (query_id != notecard_query)
        {
            return;
        }
        
        list fields = llParseStringKeepNulls(data, ["  "], [""]);

        integer num_fields = llGetListLength(fields);

        if (num_fields < 3)
        {
            llSay(0, "An error occurred while fetching the question.");
            state cancel_quiz;
        }

        list incorrect_answers;

        integer i;
        for (i = 2; i < num_fields; ++i)
        {
            incorrect_answers += llList2String(fields, i);
        }

        question_data = llList2Json(JSON_OBJECT, [
            "question", llList2String(fields, 0),
            "correct_answer", llList2String(fields, 1),
            "incorrect_answers", llList2Json(JSON_ARRAY, incorrect_answers)
        ]);
        
        if (question_number == 1)
        {
            announce("Here comes the first question...");
        }
        else if (question_number == total_questions)
        {
            announce("Here comes the last question...");
        }
        else
        {
            announce("Here comes the next question...");
        }
                        
        llSetTimerEvent(question_delay);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != quiz_starter && toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the quiz runner.");
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, "Cancel the quiz?", ["YES", "NO"], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        llListenRemove(listener);
        
        if (message == "YES")
        {
            state cancel_quiz;
        }
    }
    
    timer()
    {
        llSetTimerEvent(0);
                
        string question = llUnescapeURL(llJsonGetValue(question_data, ["question"]));
        
        correct_answer = llUnescapeURL(llJsonGetValue(question_data, ["correct_answer"]));
        
        list incorrect_answers = llJson2List(llJsonGetValue(question_data, ["incorrect_answers"]));
        
        list answers = llListRandomize(incorrect_answers + correct_answer, 1);
        
        string text = (string) question_number + ") " + question;
        
        integer i;
        for (i = 0; i < llGetListLength(answers); ++i)
        {
            string answer = llUnescapeURL(llList2String(answers, i));
            
            string letter = llChar(i + 65);
            
            if (answer == correct_answer)
            {
                correct_answer = letter;
            }
            
            text += "\n  " + letter + ") " + answer;
        }
        
        llPlaySound("question", 1);
        
        announce(text);
        
        state wait_for_answer;
    }

    state_exit()
    {
        llSetTimerEvent(0);
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* Listen for answers from players and determine if they are correct or incorrect */
state wait_for_answer
{
    state_entry()
    {
        llListen(0, "", "", "");
        llSetTimerEvent(answer_timeout);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != quiz_starter && toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the quiz runner.");
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, "Cancel the quiz?", ["YES", "NO"], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (channel == dialog_channel)
        {
            llListenRemove(listener);
            
            if (message == "YES")
            {
                state cancel_quiz;
            }
            
            return;
        }
        
        if (llStringLength(message) > 1) return;
            
        if (require_group && !llSameGroup(id))
        {
            llRegionSayTo(id, 0, "Sorry, that is restricted to the owner or group.");
            return;
        }
        
        if (llListFindList(incorrect_guessers, [id]) != -1)
        {
            llRegionSayTo(id, 0, "Sorry, you already guessed incorrectly and must wait until the next question!");
            return;
        }
        
        if (llToLower(message) == llToLower(correct_answer))
        {
            llPlaySound("ding", 1);
            
            llSay(0, correct_answer + " was the correct answer!");
            
            /* If payout is prizes... */
            if (payout == -1)
            {
                integer objects = llGetInventoryNumber(INVENTORY_OBJECT);
                integer r = (integer) llFrand(objects);
                llGiveInventory(id, llGetInventoryName(INVENTORY_OBJECT, r));
            }
            /* If payout is money... */
            else if (payout > 0)
            {
                llGiveMoney(id, payout);
                amount_paid -= payout;
            }
            
            integer index = llListFindList(scores, [id]);
            
            if (index == -1)
            {
                scores += [id, 1];
            }
            else
            {
                integer score = llList2Integer(scores, index + 1);
                
                scores = llListReplaceList(scores, [id, score + 1], index, index + 1);
            }
            
            ++question_number;
            
            if (question_number <= total_questions)
            {
                state ask_question;
            }
            else
            {
                state end_quiz;
            }
        }
        else
        {
            incorrect_guessers += id;
            llRegionSayTo(id, 0, "Sorry, " + llToUpper(message) + " is not correct. Please try again on the next question!");
        }
    }
    
    timer()
    {
        llSetTimerEvent(0);
                
        llSay(0, "Time's up! " + correct_answer + " was the correct answer!");
        
        if (payout > 0)
        {
            llGiveMoney(quiz_starter, payout);
            
            amount_paid -= payout;
        }
        
        ++question_number;
        
        if (question_number <= total_questions)
        {
            llPlaySound("fail", 1);
            
            state ask_question;
        }
        else
        {            
            state end_quiz;
        }
    }
     
    state_exit()
    {
        llSetTimerEvent(0);
        incorrect_guessers = [];
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* Finish the quiz normally */
state end_quiz
{
    state_entry()
    {
        llPlaySound("end", 1);
        
        string text = "That's the end of the quiz, thanks for playing!";
        
        integer scores_len = llGetListLength(scores);
        
        if (scores_len > 0)
        {
            text += "\n\nScores:";
            
            integer i;
            
            for (i = 0; i < llGetListLength(scores); i += 2)
            {
                key id = llList2Key(scores, i);
                integer score = llList2Integer(scores, i + 1);
                
                string name = llGetDisplayName(id);
                
                text += "\n  " + name + ": " + (string) score;
                
                if (payout > 0)
                {
                    text += " (L$" + (string) (score * payout) + ")";
                }
            }
        }
        
        announce(text);
        
        if (llGetInventoryType(category) != INVENTORY_NOTECARD)
        {
            llSay(0, "\n* " + llGetObjectName() + " is powered by the [https://opentdb.com Open Trivia Database] *");
        }
        
        llSetTimerEvent(quiz_end_time);
    }
    
    timer()
    {
        llSetTimerEvent(0);

        state ready;
    }

    state_exit()
    {
        llSetTimerEvent(0);
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}

/* End the quiz prematurely, and issue a refund to the quiz starter if necessary */
state cancel_quiz
{
    state_entry()
    {
        llPlaySound("cancel", 1);
        
        announce("The quiz was cancelled!");
        
        if (amount_paid > 0)
        {
            llRegionSayTo(quiz_starter, 0, "You will be refunded the leftover L$" + (string) amount_paid + " that you paid.");
            llGiveMoney(quiz_starter, amount_paid);
        }
        
        llSetTimerEvent(5);
    }
    
    timer()
    {
        llSetTimerEvent(0);

        state ready;
    }
    
    /* Reset script on owner transfer. */
    changed(integer change)
    {
        if (change & CHANGED_OWNER)
        {
            llResetScript();
        }
    }
}
