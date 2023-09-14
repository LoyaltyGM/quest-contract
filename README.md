# quest-contract

### **Space Functions**

- **`create_space`**:
    - **Parameters**:
        - `hub`: A mutable reference to the `SpaceHub`.
        - `name`: Name of the new space.
        - `description`: Description of the space.
        - `image_url`: Direct link to the space's image.
        - `website_url`: Official website of the space.
        - `twitter_url`: Twitter handle or link associated with the space.
    - **Description**: Initializes and creates a new space. Verifies if the sender is an authorized space creator and adjusts their allotted space creation count. Also emits a `SpaceCreated` event.

Here's a markdown-style documentation for the provided `Journey` and associated functions:

### Journey Functions

- **`create_journey`**:
    - **Parameters**:
        - `hub`: A mutable reference to the `SpaceHub`.
        - `coin`: A cryptocurrency coin of type `SUI`.
        - `space`: A mutable reference to the targeted `Space`.
        - `admin_cap`: A reference to the `SpaceAdminCap` object (or NFT), which is acquired when a space is created, ensuring administrative rights over the space.
        - ... *(Additional Parameters related to journey characteristics `name`, `description` etc)*
        - `ctx`: Likely a transaction context or related structure.
    - **Returns**: ID of the created journey.
    - **Description**: Initializes and creates a new journey. Validates the reward type and handles the journey creation fee. Emits a `JourneyCreated` event after the journey is successfully established.
- **`remove_journey`**:
    - **Parameters**:
        - `admin_cap`: A reference to the `SpaceAdminCap` object (or NFT) which is acquired when a space is created, ensuring administrative rights over the space.
        - `space`: A mutable reference to the targeted `Space`.
        - `journey_id`: ID of the journey to be removed.
    - **Description**: Deletes a specified journey and emits a `JourneyRemoved` event. It also ensures the cleanup of associated objects and tables linked with the journey.
- **`create_quest`**:
    - **Parameters**:
        - `admin_cap`: A reference to the `SpaceAdminCap` object (or NFT) which is acquired when a space is created, ensuring administrative rights over the space.
        - `space`: A mutable reference to the targeted `Space`.
        - ... *(Additional Parameters related to quest characteristics)*
        - `ctx`: Likely a transaction context or related structure.
    - **Returns**: ID of the created quest.
    - **Description**: Constructs a new quest under a specific journey. Validates space version and admin rights, then establishes the quest and emits a `QuestCreated` event.
- **`remove_quest`**:
    - **Parameters**:
        - `admin_cap`: A reference to the `SpaceAdminCap` object (or NFT) which is acquired when a space is created, ensuring administrative rights over the space.
        - `space`: A mutable reference to the targeted `Space`.
        - `journey_id`: ID of the journey under which the quest resides.
        - `quest_id`: ID of the quest to be deleted.
    - **Description**: Erases a designated quest from a particular journey and emits a `QuestRemoved` event. Also ensures the cleanup of associated objects and tables related to the quest.

---

### 2️⃣ Verifier Functions(Backend)

---

These functions are intended for backend verification systems. Normal users don't have access to these functionalities.

- **`complete_quest`**:

  Complete a quest for a given user once the verifier confirms its completion.

    - **Parameters**:
        - `_`: A capability token (`VerifierCap`) to ensure the caller has verifier privileges.
        - `space`: A mutable reference to the targeted `Space` where the quest resides.
        - `journey_id`: The identifier for the specific `Journey` that the quest belongs to.
        - `quest_id`: The identifier for the specific `Quest` to mark as completed.
        - `user`: The address of the user completing the quest.
        - `clock`: Reference to the `Clock` object for time validation purposes.
    - **Description**:
        1. Checks if the `space` is of a valid version using `check_space_version(space)`.
        2. Ensures the current time, as per the `Clock` object, is within the start and end time of the journey.
        3. Validates if the quest has been started by the user and hasn't already been marked as completed.
        4. Emits a `QuestCompleted` event with details of the space, journey, quest, and user.
        5. Increments the total completed count for the quest.
        6. Marks the quest as completed for the user.
        7. Updates the point tables for the journey and space with points earned from the quest completion.

---

### 3️⃣ User Functions

---

These functions enable users to interact with the system by starting quests, completing journeys, and receiving rewards upon journey completion.

- **`start_quest`**:

  Allows a user to start a quest within a specific journey of a space. Users are charged a fee for starting a quest.

    - **Parameters**:
        - `hub`: A mutable reference to the main `SpaceHub`.
        - `coin`: Payment by the user in the form of `Coin<SUI>`.
        - `space`: A mutable reference to the targeted `Space` where the quest resides.
        - `journey_id`: Identifier for the specific `Journey` that the quest belongs to.
        - `quest_id`: Identifier for the specific `Quest` to start.
        - `clock`: Reference to the `Clock` object for time validation.
        - `ctx`: Transaction context.
    - **Description**:
        1. Validates the version of the space.
        2. Transfers the fee for starting the quest to the verifier.
        3. Ensures the current time is within the valid time frame for the journey.
        4. Validates that the user hasn't already started or completed the quest.
        5. Marks the quest as started for the user.
- **`complete_journey`**:

  Allows a user to complete a journey if they have accumulated enough points and haven't previously completed it. On successful completion, users receive rewards based on the type specified for the journey.

    - **Parameters**:
        - `space`: A mutable reference to the targeted `Space`.
        - `journey_id`: Identifier for the specific `Journey` to complete.
        - `ctx`: Transaction context.
    - **Description**:
        1. Validates the version of the space.
        2. Validates that the user hasn't already completed the journey.
        3. Checks if the user has sufficient points to complete the journey.
        4. Emits a `JourneyCompleted` event with details of the space, journey, and user.
        5. Increments the total completion count for the journey.
        6. Marks the journey as completed for the user.
        7. Issues a reward (either an NFT or a Soulbound reward) to the user based on the journey's reward type.