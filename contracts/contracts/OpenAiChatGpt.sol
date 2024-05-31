// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "./interfaces/IOracle.sol";

contract OpenAiChatGpt {

    struct Message {
        string role;
        string content;
    }

    struct ChatRun {
        address owner;
        Message[] messages;
        uint messagesCount;
    }

    mapping(uint => ChatRun) public chatRuns;
    uint private chatRunsCount;

    event ChatCreated(address indexed owner, uint indexed chatId);

    address private owner;
    address public oracleAddress;

    event OracleAddressUpdated(address indexed newOracleAddress);

    IOracle.OpenAiRequest private config;

    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        chatRunsCount = 0;

        config = IOracle.OpenAiRequest({
        model : "gpt-4-turbo-preview",
        frequencyPenalty : 21, // > 20 for null
        logitBias : "", // empty str for null
        maxTokens : 1000, // 0 for null
        presencePenalty : 21, // > 20 for null
        responseFormat : "{\"type\":\"text\"}",
        seed : 0, // null
        stop : "", // null
        temperature : 10, // Example temperature (scaled up, 10 means 1.0), > 20 means null
        topP : 101, // Percentage 0-100, > 100 means null
        tools : "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"code_interpreter\",\"description\":\"Evaluates python code in a sandbox environment. The environment resets on every execution. You must send the whole script every time and print your outputs. Script should be pure python code that can be evaluated. It should be in python format NOT markdown. The code should NOT be wrapped in backticks. All python packages including requests, matplotlib, scipy, numpy, pandas, etc are available. Output can only be read from stdout, and stdin. Do not use things like plot.show() as it will not work. print() any output and results so you can capture the output.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"The pure python script to be evaluated. The contents will be in main.py. It should not be in markdown format.\"}},\"required\":[\"code\"]}}}]",
        toolChoice : "auto", // "none" or "auto"
        user : "" // null
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

        function createCharacterSheet(
        string memory user_name, 
        string memory character_class
    ) public returns (uint i) {
        ChatRun storage run = chatRuns[chatRunsCount];

        run.owner = msg.sender;
        Message memory newMessage;
        newMessage.content = string(abi.encodePacked("Character name:", user_name, ", character class: ", character_class, ", fill in the rest values, including abilities, features and equipments randomly base on D&D game settings"));
        newMessage.role = "user";
        run.messages.push(newMessage);
        run.messagesCount = 1;

        uint currentId = chatRunsCount;
        chatRunsCount = chatRunsCount + 1;

        string memory systemPrompt = "You are an assistant to the Game Master in an RPG game, responsible for initializing character sheets. Here is an example of a character sheet:\n\n#<Responsibilities>\n- Generate a character sheet based on the character's class.\n- There must be at least 1 and at most 3 healing potions in the miscellaneous items.\n- Do not output any other content.\n\n#<Example>\n| Name: Lucia - Class: Wizard |        |\n|-----------------|--------|\n| Race: Human     | Level: 1|\n| **HP:** 8/12    | **MP:** 14/14|\n| **EXP:** 0/100  |        |\n| **ATK:** 3      | **DEF:** 2|\n\n**Skills:**\n- Spellcrafting\n- Arcane Research\n- Detect Magic\n\n**Features:**\n- Magic Affinity\n  - Description: +1 to spell attacks/saves\n- Arcane Reservoir\n  - Description: 2 1st-level, 3 2nd-level spell slots\n\n**Equipment:**\n- Wand (1d6 spell damage)\n- Wizard's pack\n- Healing Potion x1\n- Potion of Invisibility x1\n- Scroll of Magic Missile x1\n\n**Gold:** 50 GP ---\n";

        IOracle.OpenAiRequest memory characterSheetConfig = IOracle.OpenAiRequest({
            model : "gpt-4-turbo-preview",
            frequencyPenalty : 6,
            logitBias : "",
            maxTokens : 500,
            presencePenalty : 6,
            responseFormat : "{\"type\":\"text\"}",
            seed : 0,
            stop : "",
            temperature : 9,
            topP : 9,
            tools : "",
            toolChoice : "none",
            user : ""
        });

        Message memory systemMessage;
        systemMessage.content = systemPrompt;
        systemMessage.role = "system";
        run.messages.push(systemMessage);
        run.messagesCount++;

        IOracle(oracleAddress).createOpenAiLlmCall(currentId, characterSheetConfig);
        emit ChatCreated(msg.sender, currentId);

        return currentId;
    }

    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("user")),
            "No message to respond to"
        );

        if (!compareStrings(errorMessage, "")) {
            Message memory newMessage;
            newMessage.role = "assistant";
            newMessage.content = errorMessage;
            run.messages.push(newMessage);
            run.messagesCount++;
        } else {
            if (compareStrings(response.content, "")) {
                IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            } else {
                Message memory newMessage;
                newMessage.role = "assistant";
                newMessage.content = response.content;
                run.messages.push(newMessage);
                run.messagesCount++;
            }
        }
    }

    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        ChatRun storage run = chatRuns[runId];
        require(
            compareStrings(run.messages[run.messagesCount - 1].role, "user"),
            "No function to respond to"
        );
        if (compareStrings(errorMessage, "")) {
            Message memory newMessage;
            newMessage.role = "user";
            newMessage.content = response;
            run.messages.push(newMessage);
            run.messagesCount++;
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function addMessage(string memory message, uint runId) public {
        ChatRun storage run = chatRuns[runId];
        require(
            keccak256(abi.encodePacked(run.messages[run.messagesCount - 1].role)) == keccak256(abi.encodePacked("assistant")),
            "No response to previous message"
        );
        require(
            run.owner == msg.sender, "Only chat owner can add messages"
        );

        Message memory newMessage;
        newMessage.content = message;
        newMessage.role = "user";
        run.messages.push(newMessage);
        run.messagesCount++;

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function getMessageHistoryContents(uint chatId) public view returns (string[] memory) {
        string[] memory messages = new string[](chatRuns[chatId].messages.length);
        for (uint i = 0; i < chatRuns[chatId].messages.length; i++) {
            messages[i] = chatRuns[chatId].messages[i].content;
        }
        return messages;
    }

    function getMessageHistoryRoles(uint chatId) public view returns (string[] memory) {
        string[] memory roles = new string[](chatRuns[chatId].messages.length);
        for (uint i = 0; i < chatRuns[chatId].messages.length; i++) {
            roles[i] = chatRuns[chatId].messages[i].role;
        }
        return roles;
    }

    function compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
