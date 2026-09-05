local blueprint_io = require("scripts.blueprint_io")

describe("blueprint_io.build_import_data", function()
  it("assigns sequential internal_id starting at 1, independent of entity_number", function()
    local entities, _, next_id = blueprint_io.build_import_data({
      { entity_number = 7, name = "iron-chest", position = { x = 0, y = 0 } },
      { entity_number = 12, name = "wooden-chest", position = { x = 1, y = 0 } },
    }, {})
    assert.are.equal(1, entities[1].internal_id)
    assert.are.equal("iron-chest", entities[1].raw.name)
    assert.are.equal(2, entities[2].internal_id)
    assert.are.equal("wooden-chest", entities[2].raw.name)
    assert.is_nil(entities[7])
    assert.is_nil(entities[12])
    assert.are.equal(3, next_id)
  end)

  it("returns empty tables and next_internal_id = 1 for an empty blueprint", function()
    local entities, tiles, next_id = blueprint_io.build_import_data({}, {})
    assert.are.same({}, entities)
    assert.are.same({}, tiles)
    assert.are.equal(1, next_id)
  end)

  it("indexes tiles by an \"x,y\" position key", function()
    local _, tiles = blueprint_io.build_import_data({}, {
      { name = "lab-dark-1", position = { x = -2, y = 3 } },
    })
    assert.is_not_nil(tiles["-2,3"])
    assert.are.equal("lab-dark-1", tiles["-2,3"].raw.name)
  end)

  it("preserves the raw entity table untouched (preserve-unknown-fields)", function()
    local bp_entity = {
      entity_number = 1,
      name = "assembling-machine-2",
      position = { x = 0, y = 0 },
      recipe = "iron-gear-wheel",
      request_filters = { { index = 1, name = "iron-plate", count = 100 } },
    }
    local entities = blueprint_io.build_import_data({ bp_entity }, {})
    assert.are.equal(bp_entity, entities[1].raw)
  end)
end)

describe("blueprint_io.compute_bounding_box_center", function()
  it("returns {0, 0} for an empty blueprint", function()
    local center = blueprint_io.compute_bounding_box_center({}, {})
    assert.are.same({ x = 0, y = 0 }, center)
  end)

  it("returns the single entity's own position when there is only one", function()
    local entities = { [1] = { raw = { position = { x = 5, y = -3 } } } }
    local center = blueprint_io.compute_bounding_box_center(entities, {})
    assert.are.same({ x = 5, y = -3 }, center)
  end)

  it("returns the midpoint of the bounding box across entities and tiles", function()
    local entities = {
      [1] = { raw = { position = { x = -10, y = 0 } } },
      [2] = { raw = { position = { x = 10, y = 4 } } },
    }
    local tiles = {
      ["0,-6"] = { raw = { position = { x = 0, y = -6 } } },
    }
    local center = blueprint_io.compute_bounding_box_center(entities, tiles)
    assert.are.same({ x = 0, y = -1 }, center)
  end)

  it("handles a real far-from-origin blueprint like the one that surfaced this bug", function()
    local entities = {
      [1] = { raw = { position = { x = 3, y = -142.5 } } },
      [2] = { raw = { position = { x = 2.5, y = -143.5 } } },
      [3] = { raw = { position = { x = 5, y = -142.5 } } },
    }
    local center = blueprint_io.compute_bounding_box_center(entities, {})
    assert.are.same({ x = 3.75, y = -143 }, center)
  end)
end)
