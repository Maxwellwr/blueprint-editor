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
  -- assert.near (not assert.are.same) is intentional here: 1026.3 has no
  -- exact IEEE-754 double representation, so world_position.x - offset.x
  -- lands a few ULPs off the literal 2.3/6.05 regardless of a correct
  -- implementation -- exact table equality on these fixtures is not
  -- achievable and is not a signal of a bug.
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
