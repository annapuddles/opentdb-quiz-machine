/* Open Trivia Database Quiz Machine v4.0.0 */

/** CONFIGURATION **/

/* The name of the configuration notecard in the inventory. */
string config_notecard_name = "opentdb quiz machine config";

/* URL of the Open Trivia Database API */
string opentdb_api = "https://opentdb.com/api.php";

/* URL of the list of categories in the Open Trivia Database API */
string opentdb_api_categories = "https://opentdb.com/api_category.php";

/* The encoding we want the API to use */
string opentdb_api_encoding = "url3986";

/* Whether to show OpenTDB categories, or only custom notecards. */
integer opentdb_enabled = TRUE;

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

/* The prefix for language notecards. */
string language_notecard_prefix = "opentdb quiz machine lang: ";

/* Language code used to read the appropriate language notecard. */
string language = "en";

/* The volume that sounds will be played at. */
float volume = 1.0;

/** END OF CONFIGURATION **/

/* Message strings read from the selected language notecard. */
string LANG_CHOOSE_CATEGORY;
string LANG_CANCEL;
string LANG_RANDOM;
string LANG_MORE;
string LANG_TOTAL_QUESTIONS;
string LANG_PER_QUESTION;
string LANG_QUESTION_WORTH;
string LANG_PRIZE;
string LANG_PAY_TO_PLAY;
string LANG_FREE_PLAY;
string LANG_RESTRICTED;
string LANG_STARTING_QUIZ;
string LANG_CLOSE_DIALOG;
string LANG_CHOOSE_DIFFICULTY;
string LANG_NOT_ENOUGH_QUESTIONS;
string LANG_PAYOUT_TOO_SMALL;
string LANG_NO_TRANSFER;
string LANG_TOO_FEW_PRIZES;
string LANG_QUIZ_START_1;
string LANG_QUIZ_START_2;
string LANG_QUIZ_START_3;
string LANG_QUIZ_START_4;
string LANG_PAYOUT_PRIZE;
string LANG_PAYOUT_LINDENS;
string LANG_RESTRICTED_TO_QUIZ_RUNNER;
string LANG_CANCEL_QUIZ;
string LANG_YES;
string LANG_NO;
string LANG_FETCHING;
string LANG_FETCHING_ERROR;
string LANG_FIRST_QUESTION;
string LANG_NEXT_QUESTION;
string LANG_LAST_QUESTION;
string LANG_ALREADY_GUESSED;
string LANG_CORRECT_ANSWER;
string LANG_INCORRECT_ANSWER_1;
string LANG_INCORRECT_ANSWER_2;
string LANG_TIMES_UP;
string LANG_END_QUIZ;
string LANG_SCORES;
string LANG_QUIZ_CANCELLED;
string LANG_REFUND_1;
string LANG_REFUND_2;
string LANG_FETCH_CATEGORIES_ERROR;

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

/* Name of the notecard currently being read. */
string notecard_name;

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

/* Add custom notecards to the category list and open the selection dialog. */
complete_category_setup()
{
    integer num_notecards = llGetInventoryNumber(INVENTORY_NOTECARD);
    if (num_notecards > 0)
    {
        list notecard_categories;
        integer i;
        for (i = 0; i < num_notecards; ++i)
        {
            string name = llGetInventoryName(INVENTORY_NOTECARD, i);
            if (name != config_notecard_name && llGetSubString(name, 0, llStringLength(language_notecard_prefix) - 1) != language_notecard_prefix)
            {
                notecard_categories += llList2Json(JSON_OBJECT, ["id", name, "name", name]);
            }
        }
        categories = notecard_categories + categories;
    }
    
    categories_index = 0;
    open_category_dialog();
}

/* Display a page of the category choice dialog */
open_category_dialog()
{
    string text = LANG_CHOOSE_CATEGORY;
    list buttons = [LANG_CANCEL, LANG_RANDOM, LANG_MORE];
    
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
    string total_questions_text = LANG_TOTAL_QUESTIONS;
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
                    total_questions_text += "\n" + (string) possible_total_questions + " = L$" + (string) possible_payout + " " + LANG_PER_QUESTION;
                    total_questions_buttons += (string) possible_total_questions;
                    ++buttons;
                }
            }
        }            
    }
    
    /* Display the possible numbers of questions in a dialog and let the quiz starter choose */
    llDialog(quiz_starter, total_questions_text, [LANG_CANCEL] + total_questions_buttons, dialog_channel);
}

open_payout_dialog()
{
    llDialog(quiz_starter, LANG_QUESTION_WORTH, [LANG_CANCEL, "0", "10", "20", "50", "100", "200", "500", "1000", "2000", "5000", LANG_PRIZE], dialog_channel);
}

/* In the default state, request the necessary permissions from the owner */
default
{
    state_entry()
    {        
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
                notecard_query = llGetNotecardLine(notecard_name = config_notecard_name, notecard_line = 0);
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
            if (notecard_name == config_notecard_name)
            {
                if (llGetInventoryType(language_notecard_prefix + language) == INVENTORY_NOTECARD)
                {
                    notecard_query = llGetNotecardLine(notecard_name = language_notecard_prefix + language, notecard_line = 0);
                    language = "";
                }
                else
                {
                    llOwnerSay("No notecard named \"" + language_notecard_prefix + language + "\" found! Please add one or change the language setting in the config, then reset the script.");
                }
                return;
            }
            else
            {
                notecard_name = "";
                state ready;
            }
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
                else if (name == "opentdb_enabled")
                {
                    opentdb_enabled = (integer) value;
                }
                else if (name == "volume")
                {
                    volume = (float) value;
                }
                else if (name == "language")
                {
                    language = value;
                }
                /* Localized message strings */
                else if (name == "LANG_CHOOSE_CATEGORY") LANG_CHOOSE_CATEGORY = value;
                else if (name == "LANG_CANCEL") LANG_CANCEL = value;
                else if (name == "LANG_RANDOM") LANG_RANDOM = value;
                else if (name == "LANG_MORE") LANG_MORE = value;
                else if (name == "LANG_TOTAL_QUESTIONS") LANG_TOTAL_QUESTIONS = value;
                else if (name == "LANG_PER_QUESTION") LANG_PER_QUESTION = value;
                else if (name == "LANG_QUESTION_WORTH") LANG_QUESTION_WORTH = value;
                else if (name == "LANG_PRIZE") LANG_PRIZE = value;
                else if (name == "LANG_PAY_TO_PLAY") LANG_PAY_TO_PLAY = value;
                else if (name == "LANG_FREE_PLAY") LANG_FREE_PLAY = value;
                else if (name == "LANG_RESTRICTED") LANG_RESTRICTED = value;
                else if (name == "LANG_STARTING_QUIZ") LANG_STARTING_QUIZ = value;
                else if (name == "LANG_CLOSE_DIALOG") LANG_CLOSE_DIALOG = value;
                else if (name == "LANG_CHOOSE_DIFFICULTY") LANG_CHOOSE_DIFFICULTY = value;
                else if (name == "LANG_NOT_ENOUGH_QUESTIONS") LANG_NOT_ENOUGH_QUESTIONS = value;
                else if (name == "LANG_PAYOUT_TOO_SMALL") LANG_PAYOUT_TOO_SMALL = value;
                else if (name == "LANG_NO_TRANSFER") LANG_NO_TRANSFER = value;
                else if (name == "LANG_TOO_FEW_PRIZES") LANG_TOO_FEW_PRIZES = value;
                else if (name == "LANG_QUIZ_START_1") LANG_QUIZ_START_1 = value;
                else if (name == "LANG_QUIZ_START_2") LANG_QUIZ_START_2 = value;
                else if (name == "LANG_QUIZ_START_3") LANG_QUIZ_START_3 = value;
                else if (name == "LANG_QUIZ_START_4") LANG_QUIZ_START_4 = value;
                else if (name == "LANG_PAYOUT_PRIZE") LANG_PAYOUT_PRIZE = value;
                else if (name == "LANG_PAYOUT_LINDENS") LANG_PAYOUT_LINDENS = value;
                else if (name == "LANG_RESTRICTED_TO_QUIZ_RUNNER") LANG_RESTRICTED_TO_QUIZ_RUNNER = value;
                else if (name == "LANG_CANCEL_QUIZ") LANG_CANCEL_QUIZ = value;
                else if (name == "LANG_YES") LANG_YES = value;
                else if (name == "LANG_NO") LANG_NO = value;
                else if (name == "LANG_FETCHING") LANG_FETCHING = value;
                else if (name == "LANG_FETCHING_ERROR") LANG_FETCHING_ERROR = value;
                else if (name == "LANG_FIRST_QUESTION") LANG_FIRST_QUESTION = value;
                else if (name == "LANG_NEXT_QUESTION") LANG_NEXT_QUESTION = value;
                else if (name == "LANG_LAST_QUESTION") LANG_LAST_QUESTION = value;
                else if (name == "LANG_ALREADY_GUESSED") LANG_ALREADY_GUESSED = value;
                else if (name == "LANG_CORRECT_ANSWER") LANG_CORRECT_ANSWER = value;
                else if (name == "LANG_INCORRECT_ANSWER_1") LANG_INCORRECT_ANSWER_1 = value;
                else if (name == "LANG_INCORRECT_ANSWER_2") LANG_INCORRECT_ANSWER_2 = value;
                else if (name == "LANG_TIMES_UP") LANG_TIMES_UP = value;
                else if (name == "LANG_END_QUIZ") LANG_END_QUIZ = value;
                else if (name == "LANG_SCORES") LANG_SCORES = value;
                else if (name == "LANG_QUIZ_CANCELLED") LANG_QUIZ_CANCELLED = value;
                else if (name == "LANG_REFUND_1") LANG_REFUND_1 = value;
                else if (name == "LANG_REFUND_2") LANG_REFUND_2 = value;
                else if (name == "LANG_FETCH_CATEGORIES_ERROR") LANG_FETCH_CATEGORIES_ERROR = value;
            }
        }
        
        notecard_query = llGetNotecardLine(notecard_name, ++notecard_line);
    }
    
    state_exit()
    {
        llOwnerSay("Ready!\nFree memory: " + (string) llGetFreeMemory());
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
            llSetText(LANG_PAY_TO_PLAY, text_color, 1);
        }
        else
        {
            llSetText(LANG_FREE_PLAY, text_color, 1);
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
            llRegionSayTo(toucher, 0, LANG_RESTRICTED);
        }
    }
    
    /* Begin the quiz setup when someone pays the machine */
    money(key id, integer amount)
    {
        if (require_group && !llSameGroup(id))
        {
            llRegionSayTo(id, 0, LANG_RESTRICTED);
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

        announce(llGetDisplayName(quiz_starter) + " " + LANG_STARTING_QUIZ);
        llRegionSayTo(quiz_starter, 0, LANG_CLOSE_DIALOG);
        
        setup_step = 0;
        
        if (opentdb_enabled)
        {
            llHTTPRequest(opentdb_api_categories, [], "");
        }
        else
        {
            complete_category_setup();
        }
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
            llDialog(quiz_starter, LANG_CHOOSE_DIFFICULTY, ["easy", "medium", "hard", LANG_RANDOM, LANG_CANCEL], dialog_channel);
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
            llSay(0, LANG_FETCH_CATEGORIES_ERROR);
            state cancel_quiz;
        }
        
        complete_category_setup();
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (message == LANG_CANCEL)
        {
            state cancel_quiz;
        }
        
        if (setup_step == 0)
        {
            if (message == LANG_MORE)
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
                llRegionSayTo(quiz_starter, 0, LANG_NOT_ENOUGH_QUESTIONS);
                state cancel_quiz;
            }
                    
            if (amount_paid > 0)
            {
                payout = amount_paid / total_questions;
                
                if (payout < 1)
                {
                    llRegionSayTo(quiz_starter, 0, LANG_PAYOUT_TOO_SMALL);
                    
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
                llDialog(quiz_starter, LANG_CHOOSE_DIFFICULTY, ["easy", "medium", "hard", LANG_RANDOM, LANG_CANCEL], dialog_channel);
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
            if (message == LANG_PRIZE)
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
                        llRegionSayTo(quiz_starter, 0, name + " " + LANG_NO_TRANSFER);
                    }
                }
                
                if (prizes < total_questions)
                {
                    llRegionSayTo(quiz_starter, 0, LANG_TOO_FEW_PRIZES);
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
                llRegionSayTo(quiz_starter, 0, LANG_REFUND_1 + (string) refund + " " + LANG_REFUND_2);
                llGiveMoney(quiz_starter, refund);
                amount_paid -= refund;
            }
        }
                
        question_number = 1;
                
        string text = LANG_QUIZ_START_1 + " " + (string) total_questions + " " + LANG_QUIZ_START_2 + "\n\n" + LANG_QUIZ_START_3 + "\n\n" + LANG_QUIZ_START_4;
        
        /* If payout is set to a prize... */
        if (payout == -1)
        {
            text += "\n\n" + LANG_PAYOUT_PRIZE;
        }
        /* If payout is an amount of money... */
        else if (payout > 0)
        {
            text += "\n\n" + LANG_PAYOUT_LINDENS + (string) payout + "!";
        }
        
        llPlaySound("begin", volume);
        
        announce(text);
                
        llSetTimerEvent(quiz_start_time);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != quiz_starter && toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, LANG_RESTRICTED_TO_QUIZ_RUNNER);
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, LANG_CANCEL_QUIZ, [LANG_YES, LANG_NO], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        llListenRemove(listener);
        
        if (message == LANG_YES)
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
        llSetText(LANG_FETCHING, text_color, 1);

        if (llGetInventoryType(category) == INVENTORY_NOTECARD)
        {
            notecard_query = llGetNotecardLine(category, llList2Integer(notecard_questions, question_number - 1));
        }
        else
        {
            string url = opentdb_api + "?encode=" + opentdb_api_encoding + "&amount=1";
            
            if (category != LANG_RANDOM)
            {
                url += "&category=" + category;
            }
            
            if (difficulty != LANG_RANDOM)
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
            llSay(0, LANG_FETCHING_ERROR);
            state cancel_quiz;
        }
        
        if (question_number == 1)
        {
            announce(LANG_FIRST_QUESTION);
        }
        else if (question_number == total_questions)
        {
            announce(LANG_LAST_QUESTION);
        }
        else
        {
            announce(LANG_NEXT_QUESTION);
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
            llSay(0, LANG_FETCHING_ERROR);
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
            announce(LANG_FIRST_QUESTION);
        }
        else if (question_number == total_questions)
        {
            announce(LANG_LAST_QUESTION);
        }
        else
        {
            announce(LANG_NEXT_QUESTION);
        }
                        
        llSetTimerEvent(question_delay);
    }
    
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != quiz_starter && toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, LANG_RESTRICTED_TO_QUIZ_RUNNER);
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, LANG_CANCEL_QUIZ, [LANG_YES, LANG_NO], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        llListenRemove(listener);
        
        if (message == LANG_YES)
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
        
        llPlaySound("question", volume);
        
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
            llRegionSayTo(toucher, 0, LANG_RESTRICTED_TO_QUIZ_RUNNER);
            return;
        }
        
        llListenRemove(listener);
        listener = llListen(dialog_channel, "", toucher, "");
        llDialog(toucher, LANG_CANCEL_QUIZ, [LANG_YES, LANG_NO], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (channel == dialog_channel)
        {
            llListenRemove(listener);
            
            if (message == LANG_YES)
            {
                state cancel_quiz;
            }
            
            return;
        }
        
        if (llStringLength(message) > 1) return;
            
        if (require_group && !llSameGroup(id))
        {
            llRegionSayTo(id, 0, LANG_RESTRICTED);
            return;
        }
        
        if (llListFindList(incorrect_guessers, [id]) != -1)
        {
            llRegionSayTo(id, 0, LANG_ALREADY_GUESSED);
            return;
        }
        
        if (llToLower(message) == llToLower(correct_answer))
        {
            llPlaySound("ding", volume);
            
            llSay(0, correct_answer + " " + LANG_CORRECT_ANSWER);
            
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
            llRegionSayTo(id, 0, LANG_INCORRECT_ANSWER_1 + ", " + llToUpper(message) + " " + LANG_INCORRECT_ANSWER_2);
        }
    }
    
    timer()
    {
        llSetTimerEvent(0);
                
        llSay(0, LANG_TIMES_UP + " " + correct_answer + " " + LANG_CORRECT_ANSWER);
        
        if (payout > 0)
        {
            llGiveMoney(quiz_starter, payout);
            
            amount_paid -= payout;
        }
        
        ++question_number;
        
        if (question_number <= total_questions)
        {
            llPlaySound("fail", volume);
            
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
        llPlaySound("end", volume);
        
        string text = LANG_END_QUIZ;
        
        integer scores_len = llGetListLength(scores);
        
        if (scores_len > 0)
        {
            text += "\n\n" + LANG_SCORES + ":";
            
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
        llPlaySound("cancel", volume);
        
        announce(LANG_QUIZ_CANCELLED);
        
        if (amount_paid > 0)
        {
            llRegionSayTo(quiz_starter, 0, LANG_REFUND_1 + (string) amount_paid + " " + LANG_REFUND_2);
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
