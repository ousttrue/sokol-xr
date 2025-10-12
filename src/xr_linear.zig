const xr = @import("openxr");

pub const GraphicsAPI = enum {
    VULKAN,
    OPENGL,
    OPENGL_ES,
    D3D,
    METAL,
};

// Column-major, pre-multiplied. This type does not exist in the OpenXR API and is provided for convenience.
pub const Matrix4x4f = struct {
    m: [16]f32 = .{
        1, 0, 0, 0, //
        0, 1, 0, 0, //
        0, 0, 1, 0, //
        0, 0, 0, 1, //
    },

    // Use left-multiplication to accumulate transformations.
    pub fn multiply(a: @This(), b: @This()) @This() {
        var result = @This(){};
        result.m[0] = a.m[0] * b.m[0] + a.m[4] * b.m[1] + a.m[8] * b.m[2] + a.m[12] * b.m[3];
        result.m[1] = a.m[1] * b.m[0] + a.m[5] * b.m[1] + a.m[9] * b.m[2] + a.m[13] * b.m[3];
        result.m[2] = a.m[2] * b.m[0] + a.m[6] * b.m[1] + a.m[10] * b.m[2] + a.m[14] * b.m[3];
        result.m[3] = a.m[3] * b.m[0] + a.m[7] * b.m[1] + a.m[11] * b.m[2] + a.m[15] * b.m[3];

        result.m[4] = a.m[0] * b.m[4] + a.m[4] * b.m[5] + a.m[8] * b.m[6] + a.m[12] * b.m[7];
        result.m[5] = a.m[1] * b.m[4] + a.m[5] * b.m[5] + a.m[9] * b.m[6] + a.m[13] * b.m[7];
        result.m[6] = a.m[2] * b.m[4] + a.m[6] * b.m[5] + a.m[10] * b.m[6] + a.m[14] * b.m[7];
        result.m[7] = a.m[3] * b.m[4] + a.m[7] * b.m[5] + a.m[11] * b.m[6] + a.m[15] * b.m[7];

        result.m[8] = a.m[0] * b.m[8] + a.m[4] * b.m[9] + a.m[8] * b.m[10] + a.m[12] * b.m[11];
        result.m[9] = a.m[1] * b.m[8] + a.m[5] * b.m[9] + a.m[9] * b.m[10] + a.m[13] * b.m[11];
        result.m[10] = a.m[2] * b.m[8] + a.m[6] * b.m[9] + a.m[10] * b.m[10] + a.m[14] * b.m[11];
        result.m[11] = a.m[3] * b.m[8] + a.m[7] * b.m[9] + a.m[11] * b.m[10] + a.m[15] * b.m[11];

        result.m[12] = a.m[0] * b.m[12] + a.m[4] * b.m[13] + a.m[8] * b.m[14] + a.m[12] * b.m[15];
        result.m[13] = a.m[1] * b.m[12] + a.m[5] * b.m[13] + a.m[9] * b.m[14] + a.m[13] * b.m[15];
        result.m[14] = a.m[2] * b.m[12] + a.m[6] * b.m[13] + a.m[10] * b.m[14] + a.m[14] * b.m[15];
        result.m[15] = a.m[3] * b.m[12] + a.m[7] * b.m[13] + a.m[11] * b.m[14] + a.m[15] * b.m[15];
        return result;
    }

    // Calculates the inverse of a rigid body transform.
    pub fn invertRigidBody(src: @This()) @This() {
        var result = @This(){};
        result.m[0] = src.m[0];
        result.m[1] = src.m[4];
        result.m[2] = src.m[8];
        result.m[3] = 0.0;
        result.m[4] = src.m[1];
        result.m[5] = src.m[5];
        result.m[6] = src.m[9];
        result.m[7] = 0.0;
        result.m[8] = src.m[2];
        result.m[9] = src.m[6];
        result.m[10] = src.m[10];
        result.m[11] = 0.0;
        result.m[12] = -(src.m[0] * src.m[12] + src.m[1] * src.m[13] + src.m[2] * src.m[14]);
        result.m[13] = -(src.m[4] * src.m[12] + src.m[5] * src.m[13] + src.m[6] * src.m[14]);
        result.m[14] = -(src.m[8] * src.m[12] + src.m[9] * src.m[13] + src.m[10] * src.m[14]);
        result.m[15] = 1.0;
        return result;
    }

    // Creates a projection matrix based on the specified FOV.
    pub fn createProjectionFov(
        graphicsApi: GraphicsAPI,
        fov: xr.XrFovf,
        nearZ: f32,
        farZ: f32,
    ) @This() {
        const tanLeft = @tan(fov.angleLeft);
        const tanRight = @tan(fov.angleRight);
        const tanDown = @tan(fov.angleDown);
        const tanUp = @tan(fov.angleUp);
        return createProjection(graphicsApi, tanLeft, tanRight, tanUp, tanDown, nearZ, farZ);
    }

    pub fn createProjection(
        graphicsApi: GraphicsAPI,
        tanAngleLeft: f32,
        tanAngleRight: f32,
        tanAngleUp: f32,
        tanAngleDown: f32,
        nearZ: f32,
        farZ: f32,
    ) @This() {
        const tanAngleWidth = tanAngleRight - tanAngleLeft;

        // Set to tanAngleDown - tanAngleUp for a clip space with positive Y down (Vulkan).
        // Set to tanAngleUp - tanAngleDown for a clip space with positive Y up (OpenGL / D3D / Metal).
        const tanAngleHeight = if (graphicsApi == .VULKAN)
            (tanAngleDown - tanAngleUp)
        else
            (tanAngleUp - tanAngleDown);

        // Set to nearZ for a [-1,1] Z clip space (OpenGL / OpenGL ES).
        // Set to zero for a [0,1] Z clip space (Vulkan / D3D / Metal).
        const offsetZ = if (graphicsApi == .OPENGL or graphicsApi == .OPENGL_ES)
            nearZ
        else
            0;

        var result = @This(){};
        if (farZ <= nearZ) {
            // place the far plane at infinity
            result.m[0] = 2.0 / tanAngleWidth;
            result.m[4] = 0.0;
            result.m[8] = (tanAngleRight + tanAngleLeft) / tanAngleWidth;
            result.m[12] = 0.0;

            result.m[1] = 0.0;
            result.m[5] = 2.0 / tanAngleHeight;
            result.m[9] = (tanAngleUp + tanAngleDown) / tanAngleHeight;
            result.m[13] = 0.0;

            result.m[2] = 0.0;
            result.m[6] = 0.0;
            result.m[10] = -1.0;
            result.m[14] = -(nearZ + offsetZ);

            result.m[3] = 0.0;
            result.m[7] = 0.0;
            result.m[11] = -1.0;
            result.m[15] = 0.0;
        } else {
            // normal projection
            result.m[0] = 2.0 / tanAngleWidth;
            result.m[4] = 0.0;
            result.m[8] = (tanAngleRight + tanAngleLeft) / tanAngleWidth;
            result.m[12] = 0.0;

            result.m[1] = 0.0;
            result.m[5] = 2.0 / tanAngleHeight;
            result.m[9] = (tanAngleUp + tanAngleDown) / tanAngleHeight;
            result.m[13] = 0.0;

            result.m[2] = 0.0;
            result.m[6] = 0.0;
            result.m[10] = -(farZ + offsetZ) / (farZ - nearZ);
            result.m[14] = -(farZ * (nearZ + offsetZ)) / (farZ - nearZ);

            result.m[3] = 0.0;
            result.m[7] = 0.0;
            result.m[11] = -1.0;
            result.m[15] = 0.0;
        }
        return result;
    }

    pub fn createFromRigidTransform(s: xr.XrPosef) @This() {
        return createTranslationRotationScale(
            s.position,
            s.orientation,
            .{ .x = 1, .y = 1, .z = 1 },
        );
    }

    // Creates a combined translation(rotation(scale(object))) matrix.
    pub fn createTranslationRotationScale(
        translation: xr.XrVector3f,
        rotation: xr.XrQuaternionf,
        scale: xr.XrVector3f,
    ) @This() {
        const scaleMatrix = createScale(scale.x, scale.y, scale.z);
        const rotationMatrix = createFromQuaternion(rotation);
        const translationMatrix = createTranslation(translation.x, translation.y, translation.z);
        return translationMatrix.multiply(rotationMatrix.multiply(scaleMatrix));
    }

    // Creates a scale matrix.
    pub fn createScale(x: f32, y: f32, z: f32) @This() {
        return .{
            .m = .{
                x, 0, 0, 0,
                0, y, 0, 0,
                0, 0, z, 0,
                0, 0, 0, 1,
            },
        };
    }

    // Creates a matrix from a quaternion.
    pub fn createFromQuaternion(quat: xr.XrQuaternionf) @This() {
        const x2 = quat.x + quat.x;
        const y2 = quat.y + quat.y;
        const z2 = quat.z + quat.z;

        const xx2 = quat.x * x2;
        const yy2 = quat.y * y2;
        const zz2 = quat.z * z2;

        const yz2 = quat.y * z2;
        const wx2 = quat.w * x2;
        const xy2 = quat.x * y2;
        const wz2 = quat.w * z2;
        const xz2 = quat.x * z2;
        const wy2 = quat.w * y2;

        var result = @This(){};
        result.m[0] = 1.0 - yy2 - zz2;
        result.m[1] = xy2 + wz2;
        result.m[2] = xz2 - wy2;
        result.m[3] = 0.0;

        result.m[4] = xy2 - wz2;
        result.m[5] = 1.0 - xx2 - zz2;
        result.m[6] = yz2 + wx2;
        result.m[7] = 0.0;

        result.m[8] = xz2 + wy2;
        result.m[9] = yz2 - wx2;
        result.m[10] = 1.0 - xx2 - yy2;
        result.m[11] = 0.0;

        result.m[12] = 0.0;
        result.m[13] = 0.0;
        result.m[14] = 0.0;
        result.m[15] = 1.0;
        return result;
    }

    // Creates a translation matrix.
    pub fn createTranslation(x: f32, y: f32, z: f32) @This() {
        return .{
            .m = .{
                1.0, 0.0, 0.0, 0.0, //
                0.0, 1.0, 0.0, 0.0, //
                0.0, 0.0, 1.0, 0.0, //
                x, y, z, 1.0, //
            },
        };
    }
};
