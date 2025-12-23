const c = @import("c.zig");

/// https://nodejs.org/api/n-api.html#napi_key_collection_mode
pub const KeyCollectionMode = enum(c.napi_key_collection_mode) {
    all = c.napi_key_include_prototypes,
    own_only = c.napi_key_own_only,
};

/// https://nodejs.org/api/n-api.html#napi_key_filter
pub const KeyFilter = enum(c.napi_key_filter) {
    all_properties = c.napi_key_all_properties,
    writable = c.napi_key_writable,
    enumerable = c.napi_key_enumerable,
    configurable = c.napi_key_configurable,
    skip_strings = c.napi_key_skip_strings,
    skip_symbols = c.napi_key_skip_symbols,
};

/// https://nodejs.org/api/n-api.html#napi_key_conversion
pub const KeyConversion = enum(c.napi_key_conversion) {
    keep_numbers = c.napi_key_keep_numbers,
    numbers_to_strings = c.napi_key_numbers_to_strings,
};

/// https://nodejs.org/api/n-api.html#napi_valuetype
pub const ValueType = enum(c.napi_valuetype) {
    undefined = c.napi_undefined,
    null = c.napi_null,
    boolean = c.napi_boolean,
    number = c.napi_number,
    string = c.napi_string,
    symbol = c.napi_symbol,
    object = c.napi_object,
    function = c.napi_function,
    external = c.napi_external,
    bigint = c.napi_bigint,
};

/// https://nodejs.org/api/n-api.html#napi_typedarray_type
pub const TypedarrayType = enum(c.napi_typedarray_type) {
    int8 = c.napi_int8_array,
    uint8 = c.napi_uint8_array,
    uint8_clamped = c.napi_uint8_clamped_array,
    int16 = c.napi_int16_array,
    uint16 = c.napi_uint16_array,
    int32 = c.napi_int32_array,
    uint32 = c.napi_uint32_array,
    float32 = c.napi_float32_array,
    float64 = c.napi_float64_array,
    bigint64 = c.napi_bigint64_array,
    biguint64 = c.napi_biguint64_array,

    pub fn elementSize(self: TypedarrayType) usize {
        switch (self) {
            .int8, .uint8, .uint8_clamped => return 1,
            .int16, .uint16 => return 2,
            .int32, .uint32, .float32 => return 4,
            .float64, .bigint64, .biguint64 => return 8,
        }
    }
};

/// https://nodejs.org/api/n-api.html#napi_property_attributes
pub const PropertyAttributes = enum(c.napi_property_attributes) {
    default = c.napi_default,
    writable = c.napi_writable,
    enumerable = c.napi_enumerable,
    configurable = c.napi_configurable,

    /// Used with `napi_define_class` to distinguish static properties
    /// from instance properties. Ignored by `napi_define_properties`.
    static = c.napi_static,

    /// Default for class methods.
    default_method = c.napi_default_method,

    /// Default for object properties, like in JS obj[prop].
    default_jsproperty = c.napi_default_jsproperty,
};

/// https://nodejs.org/api/n-api.html#napi_type_tag
pub const TypeTag = extern struct {
    lower: u64,
    upper: u64,
};
