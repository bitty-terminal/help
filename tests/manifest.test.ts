/**
 * Manifest and README contract checks for bitty-terminal.help.
 *
 * The authoritative manifest validator and README checker come from the
 * pinned bitty-plugin-sdk commit. This test asserts the plugin-specific
 * invariants the help plugin promises: four least-privilege grants, one lazy
 * command, one observation event, and a README that matches the SDK
 * user-documentation contract.
 */

import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import {
  checkPluginReadme,
  lintManifestSource,
  loadManifestModel,
} from "bitty-plugin-sdk";

const manifestSource = readFileSync("bitty-plugin.toml", "utf8");
const readmeSource = readFileSync("README.md", "utf8");

describe("bitty-plugin.toml", () => {
  test("passes the accepted manifest validator", () => {
    const result = lintManifestSource(manifestSource);
    const errors = result.diagnostics.filter(
      (entry) => entry.severity === "error",
    );
    expect(errors).toEqual([]);
  });

  test("declares the help identity and 0.0.31 compatibility floor", () => {
    const model = loadManifestModel(manifestSource);
    expect(model.pluginId).toBe("bitty-terminal.help");
    expect(model.name).toBe("Help");
    expect(model.version).toBe("0.0.1");
    expect(model.pluginApiRange).toBe("^1.0");
    expect(manifestSource).toContain('bitty = ">=0.0.31"');
    expect(manifestSource).not.toMatch(/bitty = ">=0\.0\.31,/);
  });

  test("requests exactly the four least-privilege grants", () => {
    const model = loadManifestModel(manifestSource);
    expect([...model.capabilities].sort()).toEqual([
      "runtime.keymaps.read",
      "ui.overlay",
      "ui.present",
      "ui.rich",
    ]);
  });

  test("never requests focusable capture, host-management, process, or filesystem authority", () => {
    const model = loadManifestModel(manifestSource);
    for (const forbidden of [
      "ui.overlay.focus",
      "config.manage",
      "runtime.inspect",
      "runtime.configure",
      "runtime.plugin-manage",
      "terminal.input.all",
      "terminal.raw-read",
      "clipboard.write",
      "process.spawn",
      "network.connect",
    ]) {
      expect(model.capabilities).not.toContain(forbidden);
    }
    expect(manifestSource).not.toContain("[[capabilities.filesystem]]");
  });

  test("reserves one lazy command and the overlay.dismissed observation event", () => {
    const model = loadManifestModel(manifestSource);
    expect([...model.commands]).toEqual(["bitty-terminal.help:toggle_help"]);
    expect([...model.events]).toEqual(["overlay.dismissed"]);
  });

  test("declares no settings and no provided services", () => {
    const model = loadManifestModel(manifestSource);
    expect(model.hasSettingsTable).toBe(false);
    expect(model.settings.size).toBe(0);
    expect(model.providedServices.size).toBe(0);
    expect(model.requiredServices.size).toBe(0);
  });
});

describe("README", () => {
  test("matches the SDK user-documentation contract", () => {
    const result = checkPluginReadme({
      manifestSource,
      readmeSource,
    });
    expect([...result.diagnostics]).toEqual([]);
    expect(result.valid).toBe(true);
  });

  test("documents the four grants, toggle_help, and the four suggested chords", () => {
    expect(readmeSource).toContain("runtime.keymaps.read");
    expect(readmeSource).toContain("ui.present");
    expect(readmeSource).toContain("bitty-terminal.help:toggle_help");
    expect(readmeSource).toContain("alt+`");
    expect(readmeSource).toContain("alt+?");
    expect(readmeSource).toContain("alt+shift+?");
    expect(readmeSource).toContain("alt+shift+/");
  });
});
