/* URL of the Open Trivia Database API */
string opentdb_api = "https://opentdb.com/api.php";

/* URL of the list of categories in the Open Trivia Database API */
string opentdb_api_categories = "https://opentdb.com/api_category.php";

/* Special payout where the machine will give out objects from its inventory instead of money */
integer PAYOUT_PRIZE = -1;

/* The encoding we want the API to use */
string encoding = "url3986";

/* The delay in seconds before a question is asked after announcing it */
float question_delay = 10;

/* The time in seconds players have to answer a question */
float answer_timeout = 30;

/* The time in seconds before the quiz setup dialogs will timeout */
float setup_timeout = 300;

/* The delay before the quiz starts after announcing it */
float quiz_start_time = 20;

/* The delay before the machine resets after a quiz ends */
float quiz_end_time = 10;

/* The maximum number of questions that can be selected */
integer max_questions = 50;

/* The channel used for dialogs */
integer dialog_channel;

/* Stores the text for the total questions choice dialog */
string total_questions_text;

/* Stores the list of buttons for the total questions choice dialog */
list total_questions_buttons;

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
list questions;

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

/* Set the overhead text of the machine */
set_text(string text)
{
    llSetText(text, <1, 1, 1>, 1);
}

/* Display a message both overhead and in nearby chat */
announce(string text)
{
    set_text(text);
    llSay(0, "\n" + text);
}

/* Give the quiz starter their remaining money back if the quiz is cancelled */
issue_refund(key id, integer amount)
{
    llRegionSayTo(id, 0, "You will be refunded the leftover L$" + (string) amount + " that you paid.");
    
    llGiveMoney(id, amount);
}

/* Increase the score of a player, or add them to the score list if this is their first correct answer */
increase_score(key id)
{
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
}

/* Display a page of the category choice dialog */
open_category_dialog()
{
    string text = "Choose a category: ";
    list buttons = ["CANCEL", "random", "MORE"];
    
    integer i;
    
    for (i = categories_index; i < llGetListLength(categories) && i < categories_index + 9; ++i)
    {
        string json = llList2String(categories, i);
        string id = llJsonGetValue(json, ["id"]);
        string name = llJsonGetValue(json, ["name"]);
        
        text += "\n" + id + ": " + name;
        
        buttons += id;
    }
    
    llDialog(quiz_starter, text, buttons, dialog_channel);
}

/* Make an HTTP request with the maximum allowed response body length */
make_http_request(string url)
{
    llHTTPRequest(url, [HTTP_BODY_MAXLENGTH, 16384], "");
}

/* Determine if the machine contains enough prizes for the selected number of questions */
integer enough_prizes()
{
    integer objects = llGetInventoryNumber(INVENTORY_OBJECT);
    
    integer i;
    
    for (i = 0; i < objects; ++i)
    {
        string name = llGetInventoryName(INVENTORY_OBJECT, i);
        
        integer perms = llGetInventoryPermMask(name, MASK_OWNER);
        
        if (!(perms & PERM_TRANSFER))
        {
            llRegionSayTo(quiz_starter, 0, name + " is not transfer and cannot be used as a prize.");
            return FALSE;
        }
        
        if (perms & PERM_COPY)
        {
            return TRUE;
        }
    }
    
    return objects >= total_questions;
}

/* In the default state, request the necessary permissions from the owner */
default
{
    state_entry()
    {
        set_text("Setting up... (touch to set permissions)");
        
        /* Get a unique channel number based on the object's key. */
        dialog_channel = 0x80000000 | (integer)("0x"+(string)llGetKey());
                        
        llSetClickAction(CLICK_ACTION_TOUCH);
        
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
            state ready;
        }
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
        category = "";
        difficulty = "";
        questions = [];
        correct_answer = "";
        scores = [];
        
        /* Set the buttons that appear in the Pay dialog */
        llSetPayPrice(PAY_DEFAULT, [10, 50, 100, 500]);
        
        /* Make it so clicking the machine initiates the Pay event */
        llSetClickAction(CLICK_ACTION_PAY);
        
        set_text("Pay me to start a quiz!");
    }
    
    /* The owner of the machine can start a quiz without paying, and has some additional options */
    touch_end(integer detected)
    {
        key toucher = llDetectedKey(0);
        
        if (toucher != llGetOwner())
        {
            llRegionSayTo(toucher, 0, "Sorry, that is restricted to the owner.");
            return;
        }
        
        quiz_starter = toucher;
                
        state choose_total_questions;
    }
    
    /* Begin the quiz setup when someone pays the machine */
    money(key id, integer amount)
    {
        amount_paid = amount;
        
        quiz_starter = id;
        
        state choose_total_questions;
    }
}

/* Get the number of questions for the quiz from the quiz starter */
state choose_total_questions
{
    state_entry()
    {
        set_text(llGetUsername(quiz_starter) + " is starting a quiz...");
        
        llSetClickAction(CLICK_ACTION_NONE);
        
        total_questions_text = "How many questions?";
        total_questions_buttons = [];
        
        /* If the owner initiated this, just display a standard set of question numbers */
        if (amount_paid == 0)
        {
            total_questions_buttons = ["1", "5", "10", "15", "20", "25", "30", "35", "40", "45", "50"];
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
        llListen(dialog_channel, "", quiz_starter, "");
        llDialog(quiz_starter, total_questions_text, ["CANCEL"] + total_questions_buttons, dialog_channel);
        llSetTimerEvent(setup_timeout);
    }
    
    /* Re-display the dialog if the machine is touched, in case it is accidentally closed */
    touch_end(integer detected)
    {
        if (llDetectedKey(0) != quiz_starter) return;
        
        llDialog(quiz_starter, total_questions_text, ["CANCEL"] + total_questions_buttons, dialog_channel);
    }
    
    /* Handle the response from the quiz starter */
    listen(integer channel, string name, key id, string message)
    {
        if (message == "CANCEL")
        {
            state cancel_quiz;
        }
        
        total_questions = (integer) message;
        
        if (total_questions < 1)
        {
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
        
        total_questions_text = "";
        total_questions_buttons = [];
        
        state choose_category;
    }
    
    /* Timeout the quiz setup if the quiz starter takes too long */
    timer()
    {
        llSetTimerEvent(0);
        
        state cancel_quiz;
    }
    
    /* Reset the dialog variables to free up memory */
    state_exit()
    {
        total_questions_text = "";
        total_questions_buttons = [];
    }
}

/* Get the category of questions that will be asked in the quiz */
state choose_category
{
    state_entry()
    {
        llListen(dialog_channel, "", quiz_starter, "");
        make_http_request(opentdb_api_categories);
        llSetTimerEvent(setup_timeout);
    }
    
    http_response(key request_id, integer status, list metadata, string body)
    {
        if (llJsonValueType(body, ["trivia_categories"]) == JSON_ARRAY)
        {
            categories = llJson2List(llJsonGetValue(body, ["trivia_categories"]));
        
            categories_index = 0;
            open_category_dialog();
        }
        else
        {
            llSay(0, "An error occurred fetching the categories.");
            state cancel_quiz;
        }
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (message == "CANCEL")
        {
            state cancel_quiz;
        }
        
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
        
        state choose_difficulty;
    }
    
    state_exit()
    {
        categories = [];
    }
}

/* Get the difficulty of the questions that will be asked */
state choose_difficulty
{
    state_entry()
    {
        llListen(dialog_channel, "", quiz_starter, "");
        llDialog(quiz_starter, "Choose a difficulty:", ["easy", "medium", "hard", "random", "CANCEL"], dialog_channel);
        llSetTimerEvent(setup_timeout);
    }
    
    touch_end(integer detected)
    {
        if (llDetectedKey(0) != quiz_starter) return;

        llDialog(quiz_starter, "Choose a difficulty:", ["easy", "medium", "hard", "random", "CANCEL"], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (message == "CANCEL") state cancel_quiz;
        
        difficulty = message;
        
        if (amount_paid == 0)
        {
            state choose_payout;
        }
        else
        {
            state begin_quiz;
        }
    }
    
    timer()
    {
        llSetTimerEvent(0);
        
        state cancel_quiz;
    }
}

/* If setup is initiated by the owner, get the payout for each question (otherwise, it is based on the amount paid to the machine) */
state choose_payout
{
    state_entry()
    {
        llListen(dialog_channel, "", quiz_starter, "");
        llDialog(quiz_starter, "How much is each question worth?", ["CANCEL", "0", "10", "20", "50", "100", "200", "500", "1000", "2000", "5000", "prize"], dialog_channel);
        llSetTimerEvent(setup_timeout);
    }
    
    touch_end(integer detected)
    {
        llDialog(quiz_starter, "How much is each question worth?", ["CANCEL", "0", "10", "20", "50", "100", "200", "500", "1000", "2000", "5000", "prize"], dialog_channel);
    }
    
    listen(integer channel, string name, key id, string message)
    {
        if (message == "CANCEL") state cancel_quiz;
        
        if (message == "prize")
        {
            if (!enough_prizes())
            {
                llRegionSayTo(quiz_starter, 0, "There are too few prizes for the total questions. Please add more and try again.");
                state cancel_quiz;
            }
            
            payout = PAYOUT_PRIZE;            
        }
        else
        {
            payout = (integer) message;
        }
        
        state begin_quiz;
    }
    
    timer()
    {
        llSetTimerEvent(0);
        
        state cancel_quiz;
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
                issue_refund(quiz_starter, refund);   
                amount_paid -= refund;
            }
        }
        
        llPreloadSound("begin");
        
        question_number = 1;
                
        string text = "A quiz of " + (string) total_questions + " questions has started!\n\nTo play, say the letter corresponding to the correct answer in nearby chat.\n\nEach person may only answer once per question!";
                
        if (payout == PAYOUT_PRIZE)
        {
            text += "\n\nEach question is worth a mystery prize!";
        }
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
        
        state fetch_question;
    }
}

state fetch_question
{
    state_entry()
    {
        set_text("Fetching question...");
        
        string url = opentdb_api + "?encode=" + encoding + "&amount=1";
        
        if (category != "random")
        {
            url += "&category=" + category;
        }
        
        if (difficulty != "random")
        {
            url += "&difficulty=" + difficulty;
        }
        
        make_http_request(url);
    }
    
    http_response(key request_id, integer status, list metadata, string body)
    {        
        questions = llJson2List(llJsonGetValue(body, ["results"]));
        
        if (llGetListLength(questions) < 1)
        {
            llSay(0, "An error occurred while fetching the question.");
            state cancel_quiz;
        }
        
        state ask_question;
    }
}

/* Display the question to the players */
state ask_question
{
    state_entry()
    {                
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
        
        llPreloadSound("question");
                
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
        
        string question_data = llList2String(questions, 0);
        
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
}

/* Listen for answers from players and determine if they are correct or incorrect */
state wait_for_answer
{
    state_entry()
    {
        llListen(0, "", "", "");
        
        llPreloadSound("ding");
        llPreloadSound("fail");
        
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
        
        if (llListFindList(incorrect_guessers, [id]) != -1)
        {
            llRegionSayTo(id, 0, "Sorry, you already guessed incorrectly and must wait until the next question!");
            return;
        }
        
        if (llToLower(message) == llToLower(correct_answer))
        {
            llPlaySound("ding", 1);
            
            llSay(0, correct_answer + " was the correct answer!");
            
            if (payout == PAYOUT_PRIZE)
            {
                integer objects = llGetInventoryNumber(INVENTORY_OBJECT);
                integer r = (integer) llFrand(objects);
                llGiveInventory(id, llGetInventoryName(INVENTORY_OBJECT, r));
            }
            else if (payout > 0)
            {
                llGiveMoney(id, payout);
                
                amount_paid -= payout;
            }
            
            increase_score(id);
            
            ++question_number;
            
            if (question_number <= total_questions)
            {
                state fetch_question;
            }
            else
            {
                llPreloadSound("end");
                llSleep(1);
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
            
            state fetch_question;
        }
        else
        {
            llPreloadSound("end");
            
            state end_quiz;
        }
    }
     
    state_exit()
    {
        incorrect_guessers = [];
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
                
                string name = llGetUsername(id);
                
                text += "\n  " + name + ": " + (string) score;
                
                if (payout > 0)
                {
                    text += " (L$" + (string) (score * payout) + ")";
                }
            }
        }
        
        announce(text);
        
        llSay(0, "\n* " + llGetObjectName() + " is powered by the [https://opentdb.com Open Trivia Database] *");
        
        llSetTimerEvent(quiz_end_time);
    }
    
    timer()
    {
        llSetTimerEvent(0);

        state ready;
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
            issue_refund(quiz_starter, amount_paid);
        }
        
        llSetTimerEvent(5);
    }
    
    timer()
    {
        llSetTimerEvent(0);

        state ready;
    }
}
