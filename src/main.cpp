#include "xatlas.h"

#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

struct InputMesh {
    uint32_t id = 0;
    std::vector<float> uvs;
    std::vector<float> positions;
    std::vector<uint32_t> indices;
    std::vector<uint32_t> faceMaterials;
};

struct InputData {
    bool autoUnwrap = false;
    uint32_t resolution = 1024;
    uint32_t padding = 4;
    float texelsPerUnit = 0.0f;
    bool bilinear = true;
    bool blockAlign = false;
    bool bruteForce = true;
    bool rotateCharts = true;
    bool rotateChartsToAxis = true;
    std::vector<InputMesh> meshes;
};

bool parseBool(int value, const char *field) {
    if (value != 0 && value != 1) {
        throw std::runtime_error(std::string(field) + " must be 0 or 1");
    }
    return value != 0;
}

template <typename T>
void readValue(std::istream &stream, T &value, const std::string &description) {
    if (!(stream >> value)) {
        throw std::runtime_error("Missing or invalid " + description);
    }
}

void expectToken(std::istream &stream, const char *expected) {
    std::string token;
    readValue(stream, token, std::string("token '") + expected + "'");
    if (token != expected) {
        throw std::runtime_error("Expected token '" + std::string(expected) + "', got '" + token + "'");
    }
}

InputData readInput(const std::string &path) {
    std::ifstream input(path.c_str(), std::ios::in);
    if (!input) {
        throw std::runtime_error("Cannot open input file: " + path);
    }

    expectToken(input, "DINUVPACK");
    int version = 0;
    readValue(input, version, "format version");
    if (version < 1 || version > 3) {
        throw std::runtime_error("Unsupported DINUVPACK version: " + std::to_string(version));
    }

    InputData data;
    size_t declaredMeshCount = std::numeric_limits<size_t>::max();
    std::string token;
    while (input >> token) {
        if (token == "resolution") {
            readValue(input, data.resolution, "resolution");
        } else if (token == "mode") {
            std::string mode;
            readValue(input, mode, "mode");
            if (mode == "pack") {
                data.autoUnwrap = false;
            } else if (mode == "auto") {
                if (version < 3) {
                    throw std::runtime_error("auto mode requires DINUVPACK version 3");
                }
                data.autoUnwrap = true;
            } else {
                throw std::runtime_error("mode must be 'pack' or 'auto'");
            }
        } else if (token == "padding") {
            readValue(input, data.padding, "padding");
        } else if (token == "texels_per_unit") {
            readValue(input, data.texelsPerUnit, "texels_per_unit");
        } else if (token == "bilinear") {
            int value = 0;
            readValue(input, value, "bilinear");
            data.bilinear = parseBool(value, "bilinear");
        } else if (token == "block_align") {
            int value = 0;
            readValue(input, value, "block_align");
            data.blockAlign = parseBool(value, "block_align");
        } else if (token == "brute_force") {
            int value = 0;
            readValue(input, value, "brute_force");
            data.bruteForce = parseBool(value, "brute_force");
        } else if (token == "rotate_charts") {
            int value = 0;
            readValue(input, value, "rotate_charts");
            data.rotateCharts = parseBool(value, "rotate_charts");
        } else if (token == "rotate_to_axis") {
            int value = 0;
            readValue(input, value, "rotate_to_axis");
            data.rotateChartsToAxis = parseBool(value, "rotate_to_axis");
        } else if (token == "mesh_count") {
            readValue(input, declaredMeshCount, "mesh_count");
        } else if (token == "mesh") {
            InputMesh mesh;
            size_t vertexCount = 0;
            size_t triangleCount = 0;
            readValue(input, mesh.id, "mesh id");
            readValue(input, vertexCount, "mesh vertex count");
            readValue(input, triangleCount, "mesh triangle count");
            if (vertexCount < 3 || triangleCount < 1) {
                throw std::runtime_error("Each mesh needs at least 3 vertices and 1 face");
            }
            if (data.autoUnwrap) {
                mesh.positions.resize(vertexCount * 3);
            } else {
                mesh.uvs.resize(vertexCount * 2);
            }
            for (size_t i = 0; i < vertexCount; ++i) {
                uint32_t index = 0;
                if (data.autoUnwrap) {
                    expectToken(input, "pos");
                } else {
                    expectToken(input, "uv");
                }
                readValue(input, index, data.autoUnwrap ? "position index" : "UV index");
                if (index != i) {
                    throw std::runtime_error("Vertex indices must be contiguous, zero-based, and ordered");
                }
                if (data.autoUnwrap) {
                    float xyz[3] = {};
                    for (float &component : xyz) {
                        readValue(input, component, "position coordinate");
                        if (!std::isfinite(component)) {
                            throw std::runtime_error("Position coordinates must be finite");
                        }
                    }
                    for (int component = 0; component < 3; ++component) {
                        mesh.positions[i * 3 + component] = xyz[component];
                    }
                } else {
                    float u = 0.0f;
                    float v = 0.0f;
                    readValue(input, u, "UV u coordinate");
                    readValue(input, v, "UV v coordinate");
                    if (!std::isfinite(u) || !std::isfinite(v)) {
                        throw std::runtime_error("UV coordinates must be finite");
                    }
                    mesh.uvs[i * 2] = u;
                    mesh.uvs[i * 2 + 1] = v;
                }
            }
            mesh.indices.resize(triangleCount * 3);
            if (!data.autoUnwrap && version >= 2) {
                mesh.faceMaterials.resize(triangleCount);
            }
            for (size_t i = 0; i < triangleCount; ++i) {
                expectToken(input, "tri");
                uint32_t triangleIndex = 0;
                readValue(input, triangleIndex, "triangle index");
                if (triangleIndex != i) {
                    throw std::runtime_error("Triangle indices must be contiguous, zero-based, and ordered");
                }
                for (int corner = 0; corner < 3; ++corner) {
                    readValue(input, mesh.indices[i * 3 + corner], "triangle vertex index");
                    if (mesh.indices[i * 3 + corner] >= vertexCount) {
                        throw std::runtime_error("Triangle references an out-of-range vertex");
                    }
                }
                if (!data.autoUnwrap && version >= 2) {
                    readValue(input, mesh.faceMaterials[i], "triangle UV-island id");
                }
            }
            expectToken(input, "endmesh");
            data.meshes.push_back(std::move(mesh));
        } else if (token == "end") {
            break;
        } else {
            throw std::runtime_error("Unknown input token: " + token);
        }
    }

    if (data.meshes.empty()) {
        throw std::runtime_error("Input contains no meshes");
    }
    if (declaredMeshCount == std::numeric_limits<size_t>::max()) {
        throw std::runtime_error("mesh_count is required");
    }
    if (declaredMeshCount != data.meshes.size()) {
        throw std::runtime_error("mesh_count does not match the number of mesh blocks");
    }
    if (data.resolution == 0 || data.resolution > 65536) {
        throw std::runtime_error("resolution must be in the range 1..65536");
    }
    if (data.padding > data.resolution / 2) {
        throw std::runtime_error("padding is too large for the requested resolution");
    }
    if (!std::isfinite(data.texelsPerUnit) || data.texelsPerUnit < 0.0f) {
        throw std::runtime_error("texels_per_unit must be finite and >= 0");
    }
    return data;
}

bool progressCallback(xatlas::ProgressCategory category, int progress, void *) {
    std::cerr << "progress " << xatlas::StringForEnum(category) << " " << progress << "\n";
    return true;
}

void writeOutput(const std::string &path, const InputData &input, const xatlas::Atlas &atlas) {
    std::ofstream output(path.c_str(), std::ios::out | std::ios::trunc);
    if (!output) {
        throw std::runtime_error("Cannot create output file: " + path);
    }

    output << std::setprecision(9);
    output << "DINUVPACK_RESULT 1\n";
    output << "atlas_width " << atlas.width << "\n";
    output << "atlas_height " << atlas.height << "\n";
    output << "atlas_count " << atlas.atlasCount << "\n";
    output << "chart_count " << atlas.chartCount << "\n";
    output << "texels_per_unit " << atlas.texelsPerUnit << "\n";
    output << "utilization_count " << atlas.atlasCount << "\n";
    for (uint32_t i = 0; i < atlas.atlasCount; ++i) {
        output << "utilization " << i << " " << atlas.utilization[i] << "\n";
    }
    output << "mesh_count " << atlas.meshCount << "\n";
    for (uint32_t meshIndex = 0; meshIndex < atlas.meshCount; ++meshIndex) {
        const xatlas::Mesh &mesh = atlas.meshes[meshIndex];
        const uint32_t inputVertexCount = input.autoUnwrap
            ? static_cast<uint32_t>(input.meshes[meshIndex].positions.size() / 3)
            : static_cast<uint32_t>(input.meshes[meshIndex].uvs.size() / 2);
        output << "mesh " << input.meshes[meshIndex].id << " " << inputVertexCount << " "
               << mesh.vertexCount << " " << mesh.indexCount << " " << mesh.chartCount << "\n";
        for (uint32_t vertexIndex = 0; vertexIndex < mesh.vertexCount; ++vertexIndex) {
            const xatlas::Vertex &vertex = mesh.vertexArray[vertexIndex];
            const float normalizedU = atlas.width == 0 ? 0.0f : vertex.uv[0] / static_cast<float>(atlas.width);
            const float normalizedV = atlas.height == 0 ? 0.0f : vertex.uv[1] / static_cast<float>(atlas.height);
            output << "vertex " << vertexIndex << " " << vertex.xref << " " << vertex.atlasIndex << " "
                   << vertex.chartIndex << " " << normalizedU << " " << normalizedV << "\n";
        }
        for (uint32_t index = 0; index < mesh.indexCount; ++index) {
            output << "index " << index << " " << mesh.indexArray[index] << "\n";
        }
        output << "endmesh\n";
    }
    output << "end\n";
    if (!output) {
        throw std::runtime_error("Failed while writing output file: " + path);
    }
}

int run(const std::string &inputPath, const std::string &outputPath) {
    const InputData input = readInput(inputPath);
    xatlas::Atlas *atlas = xatlas::Create();
    if (!atlas) {
        throw std::runtime_error("xatlas::Create failed");
    }

    try {
        xatlas::SetProgressCallback(atlas, progressCallback, nullptr);
        for (const InputMesh &mesh : input.meshes) {
            xatlas::AddMeshError error = xatlas::AddMeshError::Error;
            if (input.autoUnwrap) {
                xatlas::MeshDecl declaration;
                declaration.vertexPositionData = mesh.positions.data();
                declaration.vertexCount = static_cast<uint32_t>(mesh.positions.size() / 3);
                declaration.vertexPositionStride = sizeof(float) * 3;
                declaration.indexData = mesh.indices.data();
                declaration.indexCount = static_cast<uint32_t>(mesh.indices.size());
                declaration.indexFormat = xatlas::IndexFormat::UInt32;
                error = xatlas::AddMesh(atlas, declaration, static_cast<uint32_t>(input.meshes.size()));
            } else {
                xatlas::UvMeshDecl declaration;
                declaration.vertexUvData = mesh.uvs.data();
                declaration.vertexCount = static_cast<uint32_t>(mesh.uvs.size() / 2);
                declaration.vertexStride = sizeof(float) * 2;
                declaration.indexData = mesh.indices.data();
                declaration.indexCount = static_cast<uint32_t>(mesh.indices.size());
                declaration.indexFormat = xatlas::IndexFormat::UInt32;
                if (!mesh.faceMaterials.empty()) {
                    declaration.faceMaterialData = mesh.faceMaterials.data();
                }
                error = xatlas::AddUvMesh(atlas, declaration);
            }
            if (error != xatlas::AddMeshError::Success) {
                throw std::runtime_error(std::string(input.autoUnwrap ? "xatlas::AddMesh failed: " : "xatlas::AddUvMesh failed: ") + xatlas::StringForEnum(error));
            }
        }

        xatlas::ComputeCharts(atlas);
        xatlas::PackOptions options;
        options.resolution = input.resolution;
        options.padding = input.padding;
        options.texelsPerUnit = input.texelsPerUnit;
        options.bilinear = input.bilinear;
        options.blockAlign = input.blockAlign;
        options.bruteForce = input.bruteForce;
        options.createImage = true;
        options.rotateCharts = input.rotateCharts;
        options.rotateChartsToAxis = input.rotateChartsToAxis;
        xatlas::PackCharts(atlas, options);
        if (atlas->meshCount != input.meshes.size() || atlas->width == 0 || atlas->height == 0) {
            throw std::runtime_error("xatlas returned an incomplete atlas");
        }
        writeOutput(outputPath, input, *atlas);
        std::cout << "ok meshes=" << atlas->meshCount << " charts=" << atlas->chartCount
                  << " atlases=" << atlas->atlasCount << " size=" << atlas->width << "x" << atlas->height;
        if (atlas->atlasCount > 0) {
            std::cout << " utilization=" << std::fixed << std::setprecision(2)
                      << atlas->utilization[0] * 100.0f << "%";
        }
        std::cout << "\n";
    } catch (...) {
        xatlas::Destroy(atlas);
        throw;
    }
    xatlas::Destroy(atlas);
    return 0;
}

} // namespace

int main(int argc, char **argv) {
    if (argc != 3) {
        std::cerr << "Usage: DINUVPacker.exe <input.dinuv> <output.dinuvresult>\n";
        return 2;
    }
    try {
        return run(argv[1], argv[2]);
    } catch (const std::exception &error) {
        std::cerr << "error: " << error.what() << "\n";
        return 1;
    }
}
