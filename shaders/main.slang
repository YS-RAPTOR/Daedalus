[[vk::binding(0, 1)]]
[[vk::image_format("rgba8")]]
RWTexture2D<float4> OutImage;

[[vk::binding(0, 2)]]
cbuffer Uniforms
{
    float2 offset;
    float time;
    uint maze_size;
    uint cell_size;
    uint wall_thickness;
    uint player_radius;
    uint energy_radius;
};

[Flags]
enum Cell: uint8_t {
    south,
    east,
};

[[vk::binding(0, 0)]]
StructuredBuffer<Cell> maze_buffer;

enum EntityType: int {
    None,
    Player,
    Energy,
};

struct Entity {
    float2 position;
    float radius;
    EntityType type;
}

[[vk::binding(1, 0)]]
StructuredBuffer<Entity> entities;



[shader("compute")]
[numthreads(8, 8, 1)]
void main(uint3 GlobalInvocationID : SV_DispatchThreadID)
{
    float2 coord = GlobalInvocationID.xy;
    float maze_size_px = float(maze_size) * float(cell_size);
    float2 offset_coord = coord - offset;

    bool out_of_bounds = coord.x < offset.x || coord.y < offset.y || offset_coord.x >= maze_size_px || offset_coord.y >= maze_size_px;

    // NOTE: offset_coord is in the range [0, maze_size_px)

    // Offset from top left
    // Size of the board
    // Size of the image
    // Current Cell

    int2 cell_index = int2(floor(offset_coord)) / cell_size;
    int index = cell_index.y * maze_size + cell_index.x;

    bool color = false;
    bool4 walls = getWalls(cell_index);
    int2 cell_coord = int2(floor(offset_coord)) % cell_size;

    color |= cell_coord.y < wall_thickness && walls.x; // North wall
    color |= cell_coord.x >= cell_size - wall_thickness && walls.y; // East wall
    color |= cell_coord.y >= cell_size - wall_thickness && walls.z; // South wall
    color |= cell_coord.x < wall_thickness && walls.w; // West wall

    OutImage[int2(coord)] = float4(float3(color), 1.0f) * float(!out_of_bounds);
}

inline int getIndex(int2 cell_index) {
    return cell_index.y * maze_size + cell_index.x;
}

// NOTE: North, East, South, West
bool4 getWalls(int2 cell_index) {
    bool4 result = bool4(false);

    Cell cell = maze_buffer[getIndex(cell_index)];
    result.y = (cell.bitAnd(Cell.east)) != 0; // East wall
    result.z = (cell.bitAnd(Cell.south)) != 0; // South wall

    if (cell_index.y == 0) {
        result.x = true; // North wall at the edge
    }else {
        int2 top_cell_index = cell_index - int2(0, 1);
        Cell top_cell = maze_buffer[getIndex(top_cell_index)];
        result.x = (top_cell.bitAnd(Cell.south)) != 0; // North wall is the south wall of the cell above
    }

    if (cell_index.x == 0) {
        result.w = true; // East wall at the edge
    } else {
        int2 left_cell_index = cell_index - int2(1, 0);
        Cell left_cell = maze_buffer[getIndex(left_cell_index)];
        result.w = (left_cell.bitAnd(Cell.east)) != 0; // East wall is the east wall of the cell to the right
    }
    return result;
}
