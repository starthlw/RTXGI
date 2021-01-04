/*
* Copyright (c) 2019-2021, NVIDIA CORPORATION.  All rights reserved.
*
* NVIDIA CORPORATION and its licensors retain all intellectual property
* and proprietary rights in and to this software, related documentation
* and any modifications thereto.  Any use, reproduction, disclosure or
* distribution of this software and related documentation without an express
* license agreement from NVIDIA CORPORATION is strictly prohibited.
*/

#include "include/RTCommon.hlsl"
#include "include/RTGlobalRS.hlsl"
#include "include/RTLocalRS.hlsl"

 // ---[ Closest Hit Shader ]---

[shader("closesthit")]
void CHS(inout PackedPayload packedPayload, BuiltInTriangleIntersectionAttributes attrib)
{
    Payload payload = (Payload)0;
    payload.hitT = RayTCurrent();
    payload.hitKind = HitKind();
    payload.instanceIndex = InstanceIndex();

    // load the probeState from the first uint
    int probeState = packedPayload.albedoAndNormal.x;
    if (probeState == 1 /*PROBE_STATE_INACTIVE*/)
    {
        // inactive probe does not need any material data, so can return immediately
        packedPayload = PackPayload(payload);
        return;
    }
    // Load and interpolate the triangle's attributes (position, normal, tangent, texture coordinates)
    float3 barycentrics = float3((1.f - attrib.barycentrics.x - attrib.barycentrics.y), attrib.barycentrics.x, attrib.barycentrics.y);
    VertexAttributes v = GetInterpolatedAttributes(PrimitiveIndex(), barycentrics);

    payload.albedo = albedo;
    payload.worldPosition = mul(ObjectToWorld3x4(), float4(v.position, 1.f)).xyz;

    // Geometric normal
    payload.normal = v.normal;
    payload.normal = normalize(mul(ObjectToWorld3x4(), float4(payload.normal, 0.f)).xyz);
    payload.shadingNormal = payload.normal;

    // Albedo and Opacity
    if (albedoTexIdx > -1)
    {
        float4 bco = Textures[albedoTexIdx].SampleLevel(BilinearSampler, v.uv0, 0);
        payload.albedo = bco.rgb;
        payload.opacity = bco.a;
    }

    // Shading normal
    if (normalTexIdx > -1)
    {
        float3x3 TBN = { v.tangent, v.bitangent, payload.normal };
        payload.shadingNormal = Textures[normalTexIdx].SampleLevel(BilinearSampler, v.uv0, 0).xyz;
        payload.shadingNormal = (payload.shadingNormal * 2.f) - 1.f;                                                // Transform to [-1, 1]
        payload.shadingNormal = normalize(mul(ObjectToWorld3x4(), float4(mul(payload.shadingNormal, TBN), 0.f)));   // Transform tangent space normal to world space
    }

    // Roughness and Metallic
    if (roughnessMetallicTexIdx > -1)
    {
        float2 rm = Textures[roughnessMetallicTexIdx].SampleLevel(BilinearSampler, v.uv0, 0).gb;
        payload.roughness = rm.x;
        payload.metallic = rm.y;
    }

    // Emissive
    float3 emissive = float3(0.f, 0.f, 0.f);
    if (emissiveTexIdx > -1)
    {
        emissive = Textures[emissiveTexIdx].SampleLevel(BilinearSampler, v.uv0, 0).rgb;
    }
    payload.albedo += emissive;

    // Pack the payload
    packedPayload = PackPayload(payload);
}
