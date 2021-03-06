_ = require 'underscore'
React = require "react/addons"
ReactTestUtils = React.addons.TestUtils
CategoryPicker = require '../lib/category-picker'
{Popover} = require 'nylas-component-kit'

{Utils,
 Label,
 Folder,
 Thread,
 Actions,
 AccountStore,
 CategoryStore,
 DatabaseStore,
 TaskFactory,
 SyncbackCategoryTask,
 FocusedMailViewStore,
 TaskQueueStatusStore} = require 'nylas-exports'

describe 'CategoryPicker', ->
  beforeEach ->
    CategoryStore._categoryCache = {}

  afterEach ->
    atom.testOrganizationUnit = null

  setupFor = (organizationUnit) ->
    atom.testOrganizationUnit = organizationUnit
    @categoryClass = if organizationUnit is "label" then Label else Folder

    @inboxCategory = new @categoryClass(id: 'id-123', name: 'inbox', displayName: "INBOX")
    @archiveCategory = new @categoryClass(id: 'id-456', name: 'archive', displayName: "ArCHIVe")
    @userCategory = new @categoryClass(id: 'id-789', name: null, displayName: "MyCategory")

    spyOn(CategoryStore, "getStandardCategories").andReturn [ @inboxCategory, @archiveCategory ]
    spyOn(CategoryStore, "getUserCategories").andReturn [ @userCategory ]
    spyOn(CategoryStore, "getStandardCategory").andReturn @inboxCategory

    # By default we're going to set to "inbox". This has implications for
    # what categories get filtered out of the list.
    f = FocusedMailViewStore
    f._setMailView f._defaultMailView()

  setupForCreateNew = (orgUnit = "folder") ->
    setupFor.call(@, orgUnit)

    @testThread = new Thread(id: 't1', subject: "fake")
    @picker = ReactTestUtils.renderIntoDocument(
      <CategoryPicker thread={@testThread} />
    )

    @popover = ReactTestUtils.findRenderedComponentWithType @picker, Popover
    @popover.open()

  describe 'when using labels', ->
    beforeEach ->
      setupFor.call(@, "label")

  describe 'when using folders', ->
    beforeEach ->
      setupFor.call(@, "folder")

      @testThread = new Thread(id: 't1', subject: "fake")
      @picker = ReactTestUtils.renderIntoDocument(
        <CategoryPicker thread={@testThread} />
      )

    it 'lists the desired categories', ->
      data = @picker.state.categoryData
      # NOTE: The inbox category is not included here because it's the
      # currently focused category, which gets filtered out of the list.
      expect(data[0].id).toBe "id-456"
      expect(data[0].name).toBe "archive"
      expect(data[0].category).toBe @archiveCategory
      expect(data[1].divider).toBe true
      expect(data[1].id).toBe "category-divider"
      expect(data[2].id).toBe "id-789"
      expect(data[2].name).toBeUndefined()
      expect(data[2].category).toBe @userCategory

  describe "'create new' item", ->
    beforeEach ->
      setupForCreateNew.call @

    afterEach -> atom.testOrganizationUnit = null

    it "is not visible when the search box is empty", ->
      count = ReactTestUtils.scryRenderedDOMComponentsWithClass(@picker, 'category-create-new').length
      expect(count).toBe 0

    it "is visible when the search box has text", ->
      inputNode = React.findDOMNode(ReactTestUtils.scryRenderedDOMComponentsWithTag(@picker, "input")[0])
      ReactTestUtils.Simulate.change inputNode, target: { value: "calendar" }
      count = ReactTestUtils.scryRenderedDOMComponentsWithClass(@picker, 'category-create-new').length
      expect(count).toBe 1

    it "shows folder icon if we're using exchange", ->
      inputNode = React.findDOMNode(ReactTestUtils.scryRenderedDOMComponentsWithTag(@picker, "input")[0])
      ReactTestUtils.Simulate.change inputNode, target: { value: "calendar" }
      count = ReactTestUtils.scryRenderedDOMComponentsWithClass(@picker, 'category-create-new-folder').length
      expect(count).toBe 1

  describe "'create new' item with labels", ->
    beforeEach ->
      setupForCreateNew.call @, "label"

    it "shows label icon if we're using gmail", ->
      inputNode = React.findDOMNode(ReactTestUtils.scryRenderedDOMComponentsWithTag(@picker, "input")[0])
      ReactTestUtils.Simulate.change inputNode, target: { value: "calendar" }
      count = ReactTestUtils.scryRenderedDOMComponentsWithClass(@picker, 'category-create-new-tag').length
      expect(count).toBe 1

  describe "_onSelectCategory()", ->
    beforeEach ->
      setupForCreateNew.call @, "folder"
      spyOn(TaskFactory, 'taskForRemovingCategory').andCallThrough()
      spyOn(TaskFactory, 'taskForApplyingCategory').andCallThrough()
      spyOn(Actions, "queueTask")

    it "closes the popover", ->
      spyOn(@popover, "close")
      @picker._onSelectCategory { usage: 0, category: "asdf" }
      expect(@popover.close).toHaveBeenCalled()

    describe "when selecting a category currently on all the selected items", ->
      it "fires a task to remove the category", ->
        input =
          category: "asdf"
          usage: 1

        @picker._onSelectCategory(input)
        expect(TaskFactory.taskForRemovingCategory).toHaveBeenCalledWith
          threads: [@testThread]
          category: "asdf"
        expect(Actions.queueTask).toHaveBeenCalled()

    describe "when selecting a category not on all the selected items", ->
      it "fires a task to add the category", ->
        input =
          category: "asdf"
          usage: 0

        @picker._onSelectCategory(input)
        expect(TaskFactory.taskForApplyingCategory).toHaveBeenCalledWith
          threads: [@testThread]
          category: "asdf"
        expect(Actions.queueTask).toHaveBeenCalled()

    describe "when selecting a new category", ->
      beforeEach ->
        @input =
          newCategoryItem: true
        @picker.setState(searchValue: "teSTing!")

      it "queues a new syncback task for creating a category", ->
        @picker._onSelectCategory(@input)
        expect(Actions.queueTask).toHaveBeenCalled()
        syncbackTask = Actions.queueTask.calls[0].args[0]
        newCategory  = syncbackTask.category
        expect(newCategory instanceof @categoryClass).toBe(true)
        expect(newCategory.displayName).toBe "teSTing!"
        expect(newCategory.accountId).toBe TEST_ACCOUNT_ID

      it "queues a task for applying the category after it has saved", ->
        category = false
        resolveSave = false
        spyOn(TaskQueueStatusStore, "waitForPerformRemote").andCallFake (task) ->
          expect(task instanceof SyncbackCategoryTask).toBe true
          new Promise (resolve, reject) ->
            resolveSave = resolve

        spyOn(DatabaseStore, "findBy").andCallFake (klass, {clientId}) ->
          expect(klass).toBe(Folder)
          expect(typeof clientId).toBe("string")
          Promise.resolve(category)

        @picker._onSelectCategory(@input)

        waitsFor ->
          Actions.queueTask.callCount > 0

        runs ->
          category = Actions.queueTask.calls[0].args[0].category
          resolveSave()

        waitsFor ->
          TaskFactory.taskForApplyingCategory.calls.length is 1

        runs ->
          expect(TaskFactory.taskForApplyingCategory).toHaveBeenCalledWith
            threads: [@testThread]
            category: category
