import { decodePolyline } from "c/routeMap";

describe("c-route-map decodePolyline", () => {
  it("decodes the reference polyline from the format's documentation", () => {
    const path = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
    expect(path).toEqual([
      [38.5, -120.2],
      [40.7, -120.95],
      [43.252, -126.453]
    ]);
  });

  it("returns an empty path for no geometry", () => {
    expect(decodePolyline(null)).toEqual([]);
    expect(decodePolyline("")).toEqual([]);
  });
});
