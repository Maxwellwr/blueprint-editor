local canvas = require("scripts.canvas")

describe("canvas.snap_position", function()
  it("centers odd-sized entities on the tile center", function()
    assert.are.same({ x = 3.5, y = 4.5 }, canvas.snap_position(1, 1, { x = 3.2, y = 4.9 }))
  end)

  it("centers even-sized entities on the tile border", function()
    assert.are.same({ x = 3, y = 5 }, canvas.snap_position(2, 2, { x = 3.2, y = 4.9 }))
  end)

  it("handles mixed odd/even dimensions independently per axis", function()
    assert.are.same({ x = 3, y = 4.5 }, canvas.snap_position(2, 3, { x = 3.2, y = 4.9 }))
  end)

  it("leaves an already-snapped position untouched", function()
    assert.are.same({ x = 2.5, y = 2.5 }, canvas.snap_position(1, 1, { x = 2.5, y = 2.5 }))
    assert.are.same({ x = 5, y = 5 }, canvas.snap_position(2, 2, { x = 5, y = 5 }))
  end)
end)

describe("canvas.next_direction", function()
  it("steps a quarter turn forward by default", function()
    assert.are.equal(4, canvas.next_direction(0))
  end)

  it("wraps around at a full turn (16)", function()
    assert.are.equal(0, canvas.next_direction(12, 1))
  end)

  it("treats a nil current direction as north (0)", function()
    assert.are.equal(4, canvas.next_direction(nil, 1))
  end)

  it("steps backwards and wraps for negative steps", function()
    assert.are.equal(12, canvas.next_direction(0, -1))
  end)
end)

describe("canvas.remove_wire_references", function()
  it("removes references to the deleted entity from every other entity's wires", function()
    local entities = {
      [1] = { internal_id = 1, wires = { { target_internal_id = 2, this_connector_id = 5, target_connector_id = 5 } } },
      [2] = { internal_id = 2, wires = {
        { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 },
        { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 },
      } },
      [3] = { internal_id = 3, wires = { { target_internal_id = 2, this_connector_id = 5, target_connector_id = 5 } } },
    }
    canvas.remove_wire_references(entities, 2)
    assert.are.same({}, entities[1].wires)
    assert.are.same({}, entities[3].wires)
  end)

  it("leaves unrelated wires on other entities untouched", function()
    local entities = {
      [1] = { internal_id = 1, wires = { { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 } } },
      [2] = { internal_id = 2, wires = {} },
      [3] = { internal_id = 3, wires = { { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 } } },
    }
    canvas.remove_wire_references(entities, 2)
    assert.are.same({ { target_internal_id = 3, this_connector_id = 5, target_connector_id = 5 } }, entities[1].wires)
    assert.are.same({ { target_internal_id = 1, this_connector_id = 5, target_connector_id = 5 } }, entities[3].wires)
  end)

  it("is a no-op when the removed id has no incoming references", function()
    local entities = { [1] = { internal_id = 1, wires = {} } }
    canvas.remove_wire_references(entities, 99)
    assert.are.same({}, entities[1].wires)
  end)
end)

describe("canvas.to_local_position", function()
  -- assert.near (не assert.are.same) выбран намеренно: у 1026.3 нет точного
  -- IEEE-754 double представления, поэтому world_position.x - offset.x
  -- окажется на несколько ULP в стороне от литерала 2.3/6.05 даже при
  -- полностью корректной реализации -- точное табличное равенство на этих
  -- фикстурах недостижимо и не является признаком бага.
  it("round-trips world position back to raw.position space for a centered (new-mode) session", function()
    local session = { canvas_offset = { x = 1024, y = 0 }, blueprint_center = { x = 0, y = 0 } }
    local result = canvas.to_local_position(session, { x = 1026.3, y = 2.1 })
    assert.near(2.3, result.x, 0.0001)
    assert.near(2.1, result.y, 0.0001)
  end)

  it("accounts for a non-zero blueprint_center (edit-mode session)", function()
    local session = { canvas_offset = { x = 1024, y = 0 }, blueprint_center = { x = 3.75, y = -143 } }
    local result = canvas.to_local_position(session, { x = 1026.3, y = 2.1 })
    assert.near(6.05, result.x, 0.0001)
    assert.near(-140.9, result.y, 0.0001)
  end)
end)

describe("canvas.tile_coordinates", function()
  it("floors a fractional local position down to the containing cell", function()
    assert.are.same({ x = 3, y = 4 }, canvas.tile_coordinates({ x = 3.7, y = 4.1 }))
  end)

  it("floors negative fractional coordinates towards negative infinity", function()
    assert.are.same({ x = -4, y = -1 }, canvas.tile_coordinates({ x = -3.2, y = -0.5 }))
  end)

  it("leaves an already-integer position untouched", function()
    assert.are.same({ x = 5, y = -2 }, canvas.tile_coordinates({ x = 5, y = -2 }))
  end)
end)

describe("canvas.tile_key", function()
  it("formats coordinates as the same \"x,y\" key blueprint_io uses", function()
    assert.are.equal("3,4", canvas.tile_key(3, 4))
  end)

  it("formats negative coordinates without losing the sign", function()
    assert.are.equal("-4,-1", canvas.tile_key(-4, -1))
  end)
end)
