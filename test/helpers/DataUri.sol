// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Independent decoder for exercising the actual Base64 output, not a renderer reimplementation.
library DataUri {
    function decode(string memory uri, string memory prefix) internal pure returns (string memory) {
        bytes memory source = bytes(uri);
        bytes memory expected = bytes(prefix);
        require(source.length >= expected.length, "short data URI");
        for (uint256 i; i < expected.length; ++i) {
            require(source[i] == expected[i], "bad MIME prefix");
        }
        uint256 start = expected.length;
        uint256 encodedLength = source.length - start;
        require(encodedLength > 0 && encodedLength % 4 == 0, "bad base64 length");
        uint256 outputLength = encodedLength / 4 * 3;
        if (source[source.length - 1] == "=") --outputLength;
        if (source[source.length - 2] == "=") --outputLength;
        bytes memory result = new bytes(outputLength);
        uint256 cursor;
        for (uint256 i = start; i < source.length; i += 4) {
            uint256 word = (_digit(source[i]) << 18) | (_digit(source[i + 1]) << 12)
                | (_digit(source[i + 2]) << 6) | _digit(source[i + 3]);
            if (cursor < outputLength) result[cursor++] = bytes1(uint8(word >> 16));
            if (cursor < outputLength) result[cursor++] = bytes1(uint8(word >> 8));
            if (cursor < outputLength) result[cursor++] = bytes1(uint8(word));
        }
        return string(result);
    }

    function _digit(bytes1 c) private pure returns (uint256) {
        uint8 n = uint8(c);
        if (n >= 65 && n <= 90) return n - 65;
        if (n >= 97 && n <= 122) return n - 71;
        if (n >= 48 && n <= 57) return n + 4;
        if (c == "+") return 62;
        if (c == "/") return 63;
        if (c == "=") return 0;
        revert("invalid base64 character");
    }
}
