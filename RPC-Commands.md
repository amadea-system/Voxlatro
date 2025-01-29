# Voxlatro RPC Commands Documentation

NOTE: These commands are still very much a work in progress and subject to change.

## Overview Of Command Format

### Command Structure - Request

A RPC command from Talon to Voxlatro is generally formatted as follows:

```json
{
    // A unique identifier for the command
    // This will be returned in the response to the command
    "uuid": {string},

    // The data for command to be executed
    "data": {
        // The type of command to be executed. See the specific command documentation for the available types.
        "type": {string},

        // Additional entries for the command will vary depending on the command type. See the specific command documentation for more details.
    },

    // Not yet implemented
    "waitForFinish": {boolean},

    // Not yet implemented
    "returnCommandOutput": {boolean}
}

Here's an example of a command to select cards 1 & 5:

```json
{
    "uuid": "19292817-2e85-4c9c-babb-fa87dc6f2f70", 
    "data": {
        "type": "selectMultipleCards", 
        "cardNumbers": [1, 5]
        }, 
    "waitForFinish": false,
    "returnCommandOutput": true
}
```

### Command Structure - Response

A RPC command response from Voxlatro to Talon is generally formatted as follows:

```json
{
    // The unique identifier for the command that this response is for
    "uuid": {string},

    // If an error occurred during the command execution, this will contain the error message. Otherwise, it will be null.
    // This should cause talon to throw an exception with the error message.
    "error": {string | None},

    // If there were any warnings during the command execution, they will be listed here. Otherwise, it will be an empty list.
    "warnings": [{string}],

    // if the command was successful, this will contain the return value of the command. Otherwise, it will be null.
    // The exact format of the return value will vary depending on the command type. See the specific command documentation for more details.
    // !! NOTE: While commands are sending back a return value, I have not yet put any thought into what they are really sending back. right now, everything is just a placeholder/for debugging purposes. !!
    "returnValue": {dict | None}
    }
}
```

Here's an example of a successful response to the command to select cards 1 & 5:

```json
{
    "error": null,
    "warnings": [],
    "uuid": "19292817-2e85-4c9c-babb-fa87dc6f2f70",
    "returnValue": {
        "type": "no-action", 
        "reflection": {
            "type": "selectMultipleCards", 
            "value": [1, 5]
        }
    }
}
```

## Command List

### `selectCard`

- Type: `selectCard`
- Description: Selects a single card in the current active area.
- Parameters:
    - `cardNumber` (int): **Required** The number of the card to select. Card numbers are 1-indexed.
      - Required Value

### `selectMultipleCards`

- Type: `selectMultipleCards`
- Description: Selects multiple cards in the current active area.
- Parameters:
    - `cardNumbers` ([int]): **Required** A list of card numbers to select. Card numbers are 1-indexed.

### `toggleRunInfo`

- Type: `toggleRunInfo`
- Description: Toggles the display of the run info menu.
- Parameters: None

### `toggleOptionsMenu`

- Type: `toggleOptionsMenu`
- Description: Toggles the display of the options menu.
- Parameters: None

### `changeTab`

Note: This works on MOST but not all UI Menu's in the game.

- Type: `changeTab`
- Description: Changes the active tab in the options menu.
- Parameters:
    - Note: Either `tabNumber` or `direction` must be provided. If both are provided, `tabNumber` will take precedence.
    - `tabNumber` (int | None): **Semi-Optional** The number of the tab to switch to. Tab numbers are 1-indexed.
    - `direction` (string | None): **Semi-Optional** The direction to move the tab. Possible values are "left" and "right".

### `changeCycleOption`

This doesn't work very many places yet. Mostly in places where there are multiple cyclers. We probably need to provide a way to focus on specific cyclers?

- Type: `changeCycleOption`
- Description: Changes the active option in a cycler. (A cycler is a UI element that has a left and right arrow to cycle through options.)
- Parameters:
    - `direction` (string): **Required** The direction to move the cycler. Possible values are "left" and "right".

### `evalLua`

- Type: `evalLua`
- Description: Evaluates an arbitrary Lua expression. Note: This is a very powerful command and should be used with caution.
- Parameters:
    - `luaCode` (string): **Required** The Lua expression to evaluate.

### `toggleDeckView`

- Type: `toggleDeckView`
- Description: Toggles the display of the deck view. Either the hover menu or the full deck view menu.
- Parameters:
    - `deckViewMode` (string): **Required** The type of deck view to toggle. Possible values are "peak" and "info".

### `menuGoBack`

I think this works pretty much everywhere? May not go back to the expected place in some cases. But should always go where ever the actual back button would have taken you.

- Type: `menuGoBack`
- Description: Presses the *Back* button in the current menu.
- Parameters: None


### `moveCard`

Note: I'm very much unhappy with the way this Command is structured. It will almost certainly change in the future.

-- movement: Table. Required. This table will contain the instructions on how to move the card. There are several ways to specify how to move the card:
	--                       Move the card to the specified position. Keys: `position`
	--                       Move the card a relative amount of places left or right. Keys: `vector`
	--                       Swap the card with another card. Keys: `swapWith`
	-- -- Keys: (one must be provided)
	--   -- position: 1-based index of the card to move the card to. Optional.
	--   -- vector: number of places to move the card. Optional.
	--   -- swapWith: 1-based index of the card to swap the card with. Optional.

- Type: `moveCard`
- Description: Moves a card in the active area to a new position.
- Parameters:
    - `movement` (dict): **Required** Dictates how & where to move the card.
        - `position` (int): **Optional** The 1-based index of the card to move the card to.
        - `vector` (int): **Optional** The number of places to move the card. Positive numbers move the card to the right, negative numbers move the card to the left.
        - `swapWith` (int): **Optional** The 1-based index of the card to swap the card with. Not Yet Implemented.

### `invertCardSelection`

- Type: `invertCardSelection`
- Description: Inverts the current card selection in the active area. AKA: If there are 5 cards, and 1, 2, 4, & 5 are selected, this will deselect them and select 3.
- Parameters:
    - `exceptCards` ([int]): **Optional** A list of card numbers to exclude from the inversion. Card numbers are 1-indexed.
