package main

import "core:fmt"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"


State :: struct
{
    cellSize:        int,
    worldWidth:      int,
    worldHeight:     int,
    simulationSpeed: int,
    showActiveCells: bool,
    world:           WorldState,
}

// state for the cells
WorldState :: struct
{
    cellsOld:    []CellState,
    cellsNew:    []CellState,
    aliveCells:  int,
    activeNew:   map[int]struct{},
    activeOld:   map[int]struct{},
    // map of index to change to make
    cellChanges: map[int]CellState,
}

GuiState :: struct
{
    windowWidth, windowHeight: int,
    simSpeed:                  i32,
    cellSize:                  i32,
    showActiveCells:           bool,
    world:                     ^WorldState,
}

Vec2i :: [2]int
Vec2f :: [2]f32

CellState :: enum
{
    dead,
    alive,
}

DirectionVectors :: [8][2]int {
    {0, -1},
    {+1, -1},
    {-1, -1},
    {+1, 0},
    {0, +1},
    {-1, +1},
    {+1, +1},
    {-1, 0},
}

state: State

init :: proc(width, height, cellSize, simSpeed: int)
{
    cellCount := (width / cellSize) * (height / cellSize)

    f := make([]CellState, cellCount)
    b := make([]CellState, cellCount)


    state = State {
        cellSize,
        width,
        height,
        simSpeed,
        false,
        {cellsOld = b, cellsNew = f},
    }
}

resizeWorld :: proc(cellSize: int)
{
    //TODO: fix this function
    delete(state.world.cellsOld)
    delete(state.world.cellsNew)

    clear(&state.world.activeOld)
    clear(&state.world.activeOld)
    clear(&state.world.cellChanges)

    // for now just remake
    cellCount := (state.worldWidth / cellSize) * (state.worldHeight / cellSize)

    f := make([]CellState, cellCount)
    b := make([]CellState, cellCount)

    state.world.cellsNew = f
    state.world.cellsOld = b
    state.world.aliveCells = 0
}

changeCell :: proc(cell: Vec2i, to: CellState)
{
    cellIdx := cellToIdx(cell)
    cellToChange := state.world.cellsOld[cellIdx]

    // if the change does anything
    if cellIdx not_in state.world.cellChanges && to != cellToChange
    {
        state.world.cellChanges[cellIdx] = to

        switch to
        {
        case .alive:
            state.world.aliveCells += 1
        case .dead:
            state.world.aliveCells -= 1
        }
    }
}

//TODO: remove this?
getCellState :: proc(cell: Vec2i) -> CellState
{
    if !isInside(cell)
    {
        return .dead
    }
     else
    {
        return state.world.cellsOld[cellToIdx(cell)]
    }
}

// Coversion funcitons
//TODO: make these take the values they need for the calculation instead of using global state?

cellToWorld :: proc(cell: Vec2i) -> Vec2f
{
    return Vec2f {
        f32(cell.x) * f32(state.cellSize),
        f32(cell.y) * f32(state.cellSize),
    }
}

cellToIdx :: proc(cell: Vec2i) -> int
{
    w := state.worldWidth / state.cellSize
    return cell.y * w + cell.x
}

idxToCell :: proc(index: int) -> Vec2i
{
    w := state.worldWidth / state.cellSize
    return Vec2i{index % w, index / w}
}

isInside :: proc(cell: Vec2i) -> bool
{
    w := state.worldWidth / state.cellSize
    h := state.worldHeight / state.cellSize
    if cell.x >= w || cell.x < 0 do return false
    if cell.y >= h || cell.y < 0 do return false

    return true
}

getNewCellState :: proc(current: CellState, neighbours: int) -> CellState
{
    if current == .alive
    {
        if neighbours == 2 || neighbours == 3
        {
            return .alive
        }
        state.world.aliveCells -= 1
        return .dead
    }
     else
    {     // current == .dead
        if neighbours == 3
        {
            state.world.aliveCells += 1
            return .alive
        }
        return .dead
    }
}

updateSim :: proc()
{
    world := &state.world

    // apply changes made by user
    //TODO: deletions are not working correctly
    for key, value in world.cellChanges
    {
        // mark as active last frame
        world.activeOld[key] = {}
        for d in DirectionVectors
        {
            neighbourCell := d + idxToCell(key)
            if isInside(neighbourCell)
            {
                world.activeOld[cellToIdx(neighbourCell)] = {}
            }
        }

        // write in changes
        world.cellsOld[key] = value
    }

    clear(&world.cellChanges)
    clear(&world.activeNew)


    // write updates from front to back buffer
    for i in world.activeOld
    {
        cellState := state.world.cellsOld[i]
        currentCell := idxToCell(i)

        // count neighbours
        neighbours: int
        for d in DirectionVectors
        {
            if getCellState(currentCell + d) == .alive
            {
                neighbours += 1
            }
        }

        world.cellsNew[i] = getNewCellState(cellState, neighbours)

        // if the cell changed, add it and its neighbours to the active cells list
        if world.cellsNew[i] != world.cellsOld[i]
        {
            world.activeNew[i] = {}
            //TODO: duplicated loop
            for d in DirectionVectors
            {
                neighbourCell := d + idxToCell(i)
                if isInside(neighbourCell)
                {
                    world.activeNew[cellToIdx(neighbourCell)] = {}
                }
            }
        }

    }

    // swap buffers
    world.cellsOld, world.cellsNew = world.cellsNew, world.cellsOld

    world.activeNew, world.activeOld = world.activeOld, world.activeNew
}

// returns false if closed by the user
showSettingsPanel :: proc(guiState: ^GuiState) -> bool
{
    menuWidth := f32(guiState.windowWidth) / 2
    menuHeight := f32(guiState.windowHeight) / 2

    menuOriginX := f32(guiState.windowWidth) / 2 - (menuWidth / 2)
    menuOriginY := f32(guiState.windowHeight) / 2 - (menuHeight / 2)

    rowCount := f32(10)
    row := menuHeight / rowCount

    res := rl.GuiWindowBox(
        {menuOriginX, menuOriginY, menuWidth, menuHeight},
        "Settings",
    )
    if res != 0 do return false

    ssLabel := fmt.aprintf(
        "Simulation Speed: %vFPS",
        state.simulationSpeed,
        allocator = context.temp_allocator,
    )

    rl.GuiLabel(
        {menuOriginX, menuOriginY + row * 1, menuWidth, row},
        strings.clone_to_cstring(ssLabel, context.temp_allocator),
    )
    rl.GuiSpinner(
        {menuOriginX, menuOriginY + row * 2, menuWidth, row},
        "",
        &guiState.simSpeed,
        0,
        60,
        false,
    )

    csLabel := fmt.aprintf(
        "CellSize: %vpx",
        state.cellSize,
        allocator = context.temp_allocator,
    )

    rl.GuiLabel(
        {menuOriginX, menuOriginY + row * 3, menuWidth, row},
        strings.clone_to_cstring(csLabel, context.temp_allocator),
    )
    rl.GuiSpinner(
        {menuOriginX, menuOriginY + row * 4, menuWidth, row},
        "",
        &guiState.cellSize,
        1,
        20,
        false,
    )

    rl.GuiCheckBox(
        {menuOriginX, menuOriginY + row * 5, row, row},
        "Show active region",
        &guiState.showActiveCells,
    )

    if (rl.GuiButton(
               {menuOriginX, menuOriginY + row * rowCount, menuWidth, row},
               "Apply",
           ))
    {
        // apply changes
        state.simulationSpeed = int(guiState.simSpeed)
        state.cellSize = int(guiState.cellSize)
        state.showActiveCells = guiState.showActiveCells

        resizeWorld(int(guiState.cellSize))

        // close the menu once done
        return false
    }

    return true
}

main :: proc()
{
    WINDOW_WIDTH :: 1280
    WINDOW_HEIGHT :: 720
    DEFAULT_CELL_SIZE :: 10
    DEFAULT_SIM_SPEED :: 20

    rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "GOL")

    // init state
    init(WINDOW_WIDTH, WINDOW_HEIGHT, DEFAULT_CELL_SIZE, DEFAULT_SIM_SPEED)

    // copy current state
    guiState := GuiState {
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        i32(state.simulationSpeed),
        i32(state.cellSize),
        state.showActiveCells,
        &state.world,
    }

    generation: int

    paused := false
    showSettings := false

    lastUpdated := rl.GetTime()
    accumulator: f32

    for !rl.WindowShouldClose()
    {
        dt := rl.GetFrameTime()

        // input
        //TODO: duplicated
        if rl.IsMouseButtonDown(.LEFT) && !showSettings
        {
            mousePos := rl.GetMousePosition()
            mouseGridPos :=
                Vec2i{int(mousePos.x), int(mousePos.y)} / state.cellSize
            if isInside(mouseGridPos)
            {
                changeCell(mouseGridPos, .alive)
            }
        }

        if rl.IsMouseButtonDown(.RIGHT) && !showSettings
        {
            mousePos := rl.GetMousePosition()
            mouseGridPos :=
                Vec2i{int(mousePos.x), int(mousePos.y)} / state.cellSize
            if isInside(mouseGridPos)
            {
                changeCell(mouseGridPos, .dead)
            }
        }

        if rl.IsKeyPressed(.SPACE)
        {
            // toggle paused
            paused = !paused
        }

        if rl.IsKeyPressed(.S)
        {
            showSettings = true
        }

        if rl.IsKeyPressed(.R)
        {
            // reset world
            slice.zero(state.world.cellsOld)
            slice.zero(state.world.cellsNew)
            clear(&state.world.activeNew)
            clear(&state.world.activeOld)
            state.world.aliveCells = 0
            clear(&state.world.cellChanges)
            generation = 0
        }

        if rl.IsKeyPressed(.PERIOD) && paused
        {
            updateSim()
        }

        if !paused do accumulator += dt
        // update
        step := 1.0 / f32(state.simulationSpeed)
        if !paused && accumulator >= step
        {
            accumulator -= step

            updateSim()
            generation += 1
        }


        // draw
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        // TODO: store the alive cells so that we dont have to loop through all cells
        // would also allow us to remove the second loop to draw the cell changes
        for cell, i in state.world.cellsNew
        {
            if cell == .alive
            {
                cellPos := cellToWorld(idxToCell(i))
                size := rl.Vector2{f32(state.cellSize), f32(state.cellSize)}

                rl.DrawRectangleV(cellPos, size, rl.WHITE)

            }
            // show active cells
            if state.showActiveCells
            {
                if i in state.world.activeNew
                {
                    cellPos := cellToWorld(idxToCell(i))
                    size := rl.Vector2 {
                        f32(state.cellSize),
                        f32(state.cellSize),
                    }
                    rl.DrawRectangleV(
                        cellPos,
                        size,
                        rl.Color{0, 128, 128, 128},
                    )
                }

            }
        }

        //WARN: maybe temp
        for key, value in state.world.cellChanges
        {
            if value == .alive
            {
                cellPos := cellToWorld(idxToCell(key))
                size := rl.Vector2{f32(state.cellSize), f32(state.cellSize)}
                rl.DrawRectangleV(cellPos, size, rl.WHITE)
            }
        }


        fps := 1 / dt
        rl.DrawText(
            strings.clone_to_cstring(
                fmt.aprintf(
                    "Alive Cells: %v\nGeneration: %v\nFPS: %v",
                    state.world.aliveCells,
                    generation,
                    fps,
                    allocator = context.temp_allocator,
                ),
                context.temp_allocator,
            ),
            30,
            30,
            20,
            rl.WHITE,
        )


        if showSettings
        {
            open := showSettingsPanel(&guiState)

            if !open do showSettings = false
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
    rl.CloseWindow()
}
