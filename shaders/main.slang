[[vk::binding(0, 1)]]
[[vk::image_format("rgba8")]]
RWTexture2D<float4> OutImage;

[[vk::binding(0, 2)]]
cbuffer Uniforms
{
    float2 offset;
    uint2 highlight_cell;
    float time;
    uint maze_size;
    uint cell_size;
    uint wall_thickness;
    uint lever_radius;
};

[Flags]
enum Cell: uint8_t {
    South,
    East,
    Lever,
    SouthDoor,
    EastDoor,
    Path,
    Corner,
};

[[vk::binding(0, 0)]]
StructuredBuffer<Cell> maze_buffer;

enum EntityType: int {
    None,
    Player,
    Target,
};

struct Entity {
    float2 position;
    float radius;
    EntityType type;
}

static const float4[] entity_color = {
    float4(0.0f, 0.0f, 0.0f, 0.0f), // None
    float4(0.078f, 0.722f, 0.651f, 1.0f), // #14b8a6
    float4(0.882, 0.114, 0.282, 1.0), // #E11D48
};

static const float4 lever_color = float4(0.988, 0.8, 0.149, 1.0); // #FDE047
static const float3 path_color = float3 (0.278, 0.333, 0.412); // #475569
static const float3 corner_color_offset = float3(0.5, 0.5, 0.5); // #888888
static const float3 highlight_color = float3(0.9098, 0.4745, 0.9765); // #e879f9

[[vk::binding(1, 0)]]
StructuredBuffer<Entity> entities;

[shader("compute")]
[numthreads(8, 8, 1)]
void main(uint3 GlobalInvocationID : SV_DispatchThreadID)
{
    let coord: float2 = GlobalInvocationID.xy;
    let maze_size_px = float(maze_size) * float(cell_size);
    let offset_coord = coord - offset;

    let out_of_bounds = coord.x < offset.x || coord.y < offset.y || offset_coord.x >= maze_size_px || offset_coord.y >= maze_size_px;

    // NOTE: offset_coord is in the range [0, maze_size_px)

    // Draw Maze
    let cell_index = int2(floor(offset_coord)) / cell_size;
    let index = cell_index.y * maze_size + cell_index.x;

    var color = false;
    let walls = getWalls(cell_index);
    let cell_coord = int2(floor(offset_coord)) % cell_size;

    let cell = maze_buffer[getIndex(cell_index)];
    let is_path = (cell.bitAnd(Cell.Path)) != 0;
    let is_corner = (cell.bitAnd(Cell.Corner)) != 0;
    let is_highlighted = cell_index.x == highlight_cell.x && cell_index.y == highlight_cell.y;
    let has_lever = (cell.bitAnd(Cell.Lever)) != 0;


    color |= cell_coord.y < wall_thickness && walls.x; // North wall
    color |= cell_coord.x >= cell_size - wall_thickness && walls.y; // East wall
    color |= cell_coord.y >= cell_size - wall_thickness && walls.z; // South wall
    color |= cell_coord.x < wall_thickness && walls.w; // West wall

    OutImage[int2(coord)] = float4(
        (path_color * float3(is_path) + corner_color_offset * float3(is_corner)),
        1.0f,
    );
    OutImage[int2(coord)] = float4(
        (highlight_color * float3(is_highlighted) + OutImage[int2(coord)].xyz * float3(!is_highlighted)),
        1.0f,
    );

    // Draw Entities
    let uv = offset_coord / maze_size_px;
    for (uint i = 0; i < entities.getCount(); ++i) {
        let entity = entities[i];
        if(entity.type == EntityType::None) continue;
        OutImage[int2(coord)] = DrawSmoothCircle(
            uv,
            entity.position * cell_size / maze_size_px,
            entity.radius / maze_size_px,
            0.0001f,
            entity_color[int(entity.type)],
            OutImage[int2(coord)],
        );
    }


    if (has_lever) {
        OutImage[int2(coord)] = DrawSmoothCircle(
            uv,
            float2(cell_index) * cell_size / maze_size_px + 0.5f * cell_size / maze_size_px,
            float(lever_radius) / maze_size_px,
            0.003f,
            lever_color,
            OutImage[int2(coord)],
        );
    }

    OutImage[int2(coord)] = float4(
        float3(color) + float(!color) * OutImage[int2(coord)].xyz,
        1.0f,
    ) * float(!out_of_bounds);
}

float4 DrawSmoothCircle(float2 uv, float2 center, float radius, float edgeSoftness, float4 circleColor, float4 bgColor)
{
    let dist = distance(uv, center);
    let t = smoothstep(radius + edgeSoftness, radius - edgeSoftness, dist);
    let color = lerp(bgColor, circleColor, t);
    return color;
}

inline int getIndex(int2 cell_index) {
    return cell_index.y * maze_size + cell_index.x;
}

// NOTE: North, East, South, West
bool4 getWalls(int2 cell_index) {
    var result = bool4(false);

    let cell = maze_buffer[getIndex(cell_index)];
    result.y = (cell.bitAnd(Cell.East)) != 0; // East wall
    result.z = (cell.bitAnd(Cell.South)) != 0; // South wall

    if (cell_index.y == 0) {
        result.x = true; // North wall at the edge
    }else {
        let top_cell_index = cell_index - int2(0, 1);
        let top_cell = maze_buffer[getIndex(top_cell_index)];
        result.x = (top_cell.bitAnd(Cell.South)) != 0; // North wall is the south wall of the cell above
    }

    if (cell_index.x == 0) {
        result.w = true; // East wall at the edge
    } else {
        let left_cell_index = cell_index - int2(1, 0);
        let left_cell = maze_buffer[getIndex(left_cell_index)];
        result.w = (left_cell.bitAnd(Cell.East)) != 0; // East wall is the east wall of the cell to the right
    }
    return result;
}
