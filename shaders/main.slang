struct VertexOutput
{
    nointerpolation int a : SOME_VALUE;
    float3              b : SV_Position;
};

[shader("pixel")]
float4 px() : SV_Target
{
    return float4(1, 0, 0, 1);
}

[shader("vertex")]
VertexOutput vx()
{
    VertexOutput out;
    out.a = 0;
    out.b = float3(0, 1, 0);
    return out;
}
