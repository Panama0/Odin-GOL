package main

import "core:fmt"
import "core:math"
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
    showCameraDebug: bool,
    world:           WorldState,
}

// state for the cells
WorldState :: struct
{
    cellsOld:       []CellState,
    cellsNew:       []CellState,
    aliveCellCount: int,
    activeNew:      map[int]struct{},
    activeOld:      map[int]struct{},
    // map of index to change to make
    cellChanges:    map[int]CellState,
    aliveCells:     map[int]struct{},
}

GuiState :: struct
{
    windowWidth, windowHeight: int,
    simSpeed:                  i32,
    cellSize:                  i32,
    showActiveCells:           bool,
    showCameraDebug:           bool,
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
    state.world.aliveCellCount = 0
}

editCell :: proc(cell: Vec2i, to: CellState)
{
    cellIdx := cellToIdx(cell)

    // only add the change if it is not duplicated
    if cellIdx not_in state.world.cellChanges ||
       state.world.cellChanges[cellIdx] != to
    {
        state.world.cellChanges[cellIdx] = to

        switch to
        {
        case .alive:
            state.world.aliveCellCount += 1
            state.world.aliveCells[cellIdx] = {}
        case .dead:
            state.world.aliveCellCount -= 1
            delete_key(&state.world.aliveCells, cellIdx)
        }

    }
}

// Conversion Functions

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

simulateCell :: proc(
    current: CellState,
    cellIndex: int,
    neighbours: int,
) -> CellState
{
    if current == .alive
    {
        if neighbours == 2 || neighbours == 3
        {
            // lives on
            return .alive
        }
        // dies
        state.world.aliveCellCount -= 1

        delete_key(&state.world.aliveCells, cellIndex)

        return .dead
    }
     else
    {     // current == .dead
        if neighbours == 3
        {
            // reproduces
            state.world.aliveCellCount += 1

            state.world.aliveCells[cellIndex] = {}

            return .alive
        }
        // continues to be dead
        return .dead
    }
}

updateSim :: proc()
{
    world := &state.world
    // swap buffers
    world.cellsOld, world.cellsNew = world.cellsNew, world.cellsOld

    world.activeNew, world.activeOld = world.activeOld, world.activeNew

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
            if isInside(currentCell) &&
               world.cellsOld[cellToIdx(currentCell + d)] == .alive
            {
                neighbours += 1
            }
        }

        world.cellsNew[i] = simulateCell(cellState, i, neighbours)

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
    rl.GuiCheckBox(
        {menuOriginX, menuOriginY + row * 6, row, row},
        "Show camera debug",
        &guiState.showCameraDebug,
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
        state.showCameraDebug = guiState.showCameraDebug

        resizeWorld(int(guiState.cellSize))

        // close the menu once done
        return false
    }

    return true
}

// clamp camera such that the outside of the world is not shown
clampCamera :: proc(worldDimensions: Vec2f, camera: ^rl.Camera2D)
{
    // view width in world space units
    viewWidth := f32(worldDimensions.x) / camera.zoom
    viewHeight := f32(worldDimensions.y) / camera.zoom

    camera.target.x = clamp(
        camera.target.x,
        (viewWidth / 2),
        f32(worldDimensions.x) - (viewWidth / 2),
    )
    camera.target.y = clamp(
        camera.target.y,
        viewHeight / 2,
        f32(worldDimensions.y) - (viewHeight / 2),
    )
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

    // TODO: clean this up?

    // copy current state
    guiState := GuiState {
        WINDOW_WIDTH,
        WINDOW_HEIGHT,
        i32(state.simulationSpeed),
        i32(state.cellSize),
        state.showActiveCells,
        state.showCameraDebug,
        &state.world,
    }

    generation: int

    paused := false
    showSettings := false

    accumulator: f32

    screenMiddle := rl.Vector2{WINDOW_WIDTH, WINDOW_HEIGHT} / 2
    camera := rl.Camera2D{screenMiddle, screenMiddle, 0, 1}

    InputModes :: enum
    {
        normalMode,
        settingsMode,
        cameraMode,
    }

    mode := InputModes{}

    for !rl.WindowShouldClose()
    {
        dt := rl.GetFrameTime()

        // input

        if rl.IsKeyDown(.LEFT_SHIFT)
        {
            mode = .cameraMode

        }
         else if rl.IsKeyPressed(.S)
        {
            mode = .settingsMode
        }

        switch mode
        {
        case .normalMode:
            handleClick :: proc(
                camera: rl.Camera2D,
                mousePos: rl.Vector2,
                action: CellState,
            )
            {
                mouseWorldPos := rl.GetScreenToWorld2D(mousePos, camera)
                mouseGridPos :=
                    Vec2i{int(mouseWorldPos.x), int(mouseWorldPos.y)} /
                    state.cellSize
                if isInside(mouseGridPos)
                {
                    editCell(mouseGridPos, action)
                }

            }

            if rl.IsMouseButtonDown(.LEFT)
            {
                handleClick(camera, rl.GetMousePosition(), .alive)
            }

            if rl.IsMouseButtonDown(.RIGHT)
            {
                handleClick(camera, rl.GetMousePosition(), .dead)
            }

            if wheel := rl.GetMouseWheelMove(); wheel != 0
            {
                mousePos := rl.GetMousePosition()
                // world position under mouse BEFORE zoom change
                mouseWorldBefore := rl.GetScreenToWorld2D(mousePos, camera)

                // compute new zoom
                scale := 0.2 * wheel
                zm := math.exp(math.ln(camera.zoom) + scale)
                camera.zoom = clamp(zm, 1.0, 64.0)

                // recompute target so mouseWorldBefore stays anchored under the mouse
                camera.target.x =
                    mouseWorldBefore.x -
                    (mousePos.x - camera.offset.x) / camera.zoom
                camera.target.y =
                    mouseWorldBefore.y -
                    (mousePos.y - camera.offset.y) / camera.zoom

                // clamp target to world bounds (use world size, not window size)
                clampCamera(
                    {f32(state.worldWidth), f32(state.worldHeight)},
                    &camera,
                )
            }

            if rl.IsKeyPressed(.SPACE)
            {
                paused = !paused
            }


            if rl.IsKeyPressed(.R)
            {
                // TODO: fix this

                // reset world
                slice.zero(state.world.cellsOld)
                slice.zero(state.world.cellsNew)
                clear(&state.world.activeNew)
                clear(&state.world.activeOld)
                state.world.aliveCellCount = 0
                clear(&state.world.cellChanges)
                clear(&state.world.aliveCells)
                generation = 0
            }

            // step simulation 1 at a time
            if rl.IsKeyPressed(.PERIOD) && paused
            {
                updateSim()
            }
        case .settingsMode:
            showSettings = true
        case .cameraMode:
            if rl.IsMouseButtonDown(.LEFT)
            {
                delta := rl.GetMouseDelta() * (-1.0 / camera.zoom)
                camera.target += delta

                clampCamera(
                    {f32(state.worldWidth), f32(state.worldHeight)},
                    &camera,
                )
            }
             else
            {
                mode = .normalMode
            }
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

        rl.BeginMode2D(camera)

        if state.showCameraDebug
        {
            worldDim := rl.Vector2 {
                f32(state.worldWidth),
                f32(state.worldHeight),
            }
            rl.DrawRectangleV({0, 0}, worldDim, rl.DARKBLUE)
            rl.DrawCircleV(camera.target, 10, rl.RED)
            rl.DrawCircleV(
                ((worldDim / 2) - camera.offset) / camera.zoom + camera.target,
                10,
                rl.BLUE,
            )
        }

        for idx in state.world.aliveCells
        {
            cellPos := cellToWorld(idxToCell(idx))
            size := rl.Vector2{f32(state.cellSize), f32(state.cellSize)}
            rl.DrawRectangleV(cellPos, size, rl.WHITE)
        }

        // show active cells
        if state.showActiveCells
        {
            for idx in state.world.activeNew
            {
                cellPos := cellToWorld(idxToCell(idx))
                size := rl.Vector2{f32(state.cellSize), f32(state.cellSize)}
                rl.DrawRectangleV(cellPos, size, rl.Color{0, 128, 128, 128})
            }

        }

        rl.EndMode2D()

        fps := 1 / dt
        rl.DrawText(
            strings.clone_to_cstring(
                fmt.aprintf(
                    "Alive Cells: %v\nGeneration: %v\nFPS: %v",
                    state.world.aliveCellCount,
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

            if !open
            {
                showSettings = false
                mode = .normalMode
            }
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
    rl.CloseWindow()
}
