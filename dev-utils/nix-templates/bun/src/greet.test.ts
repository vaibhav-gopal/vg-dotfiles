import { expect, test } from "bun:test";

import { greeting } from "./greet.ts";

test("greets by name", () => {
  expect(greeting("nix")).toBe("Hello, nix!");
});
