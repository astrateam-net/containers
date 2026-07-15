package net.astrateam.astrai18n;

import java.lang.reflect.Method;

/**
 * Build-time check that {@link Astrai18nAgent}'s seams still exist in the image it is being
 * overlaid onto. Run against the application classpath during the Docker build; exits non-zero
 * if anything it instruments has moved.
 *
 * <p>Why this exists: the agent is a <em>runtime</em> Byte Buddy transformer. If upstream renames
 * a provider or its {@code get} method, Byte Buddy simply matches nothing — no error, no warning.
 * The image builds, the tests pass, the app boots, and the feature set silently falls back to the
 * OSS default. Every other app in this repo patches at build time and can refuse to build; this
 * one could not, which made it the only unlock that could rot unnoticed. This closes that gap, so
 * a moved seam fails the build instead of shipping a dead unlock.
 *
 * <p>Deliberately uses {@code initialize=false} on {@link Class#forName}: the providers are Spring
 * beans, and running their static initialisers here would drag in context that is not available
 * during a build.
 */
public final class VerifyAnchors {

  private static final String PUBLIC_PROVIDER =
      "io.tolgee.ee.component.PublicEnabledFeaturesProvider";
  private static final String OSS_PROVIDER =
      "io.tolgee.component.enabledFeaturesProvider.EnabledFeaturesProviderOssImpl";
  private static final String FEATURE_ENUM = "io.tolgee.constants.Feature";

  private VerifyAnchors() {}

  public static void main(String[] args) {
    ClassLoader cl = VerifyAnchors.class.getClassLoader();
    int failures = 0;

    // Both providers must still be instrumentable: the agent matches either, and the EE one is
    // the @Primary bean that actually serves the feature set in this image.
    for (String provider : new String[] {PUBLIC_PROVIDER, OSS_PROVIDER}) {
      Class<?> type = load(provider, cl);
      if (type == null) {
        System.err.println("astrai18n: MISSING class " + provider);
        failures++;
        continue;
      }
      if (!hasGet(type)) {
        System.err.println("astrai18n: " + provider + " no longer declares a get(..) method");
        failures++;
        continue;
      }
      System.out.println("astrai18n: OK  " + provider + "#get");
    }

    // The advice resolves this reflectively and calls values(); if it moves, the agent throws at
    // runtime inside suppressed advice and the feature set silently stays empty.
    Class<?> feature = load(FEATURE_ENUM, cl);
    if (feature == null) {
      System.err.println("astrai18n: MISSING enum " + FEATURE_ENUM);
      failures++;
    } else if (!feature.isEnum()) {
      System.err.println("astrai18n: " + FEATURE_ENUM + " is no longer an enum");
      failures++;
    } else {
      try {
        Object values = feature.getMethod("values").invoke(null);
        int n = java.lang.reflect.Array.getLength(values);
        if (n == 0) {
          System.err.println("astrai18n: " + FEATURE_ENUM + ".values() is empty");
          failures++;
        } else {
          System.out.println("astrai18n: OK  " + FEATURE_ENUM + ".values() -> " + n + " features");
        }
      } catch (ReflectiveOperationException e) {
        System.err.println("astrai18n: " + FEATURE_ENUM + ".values() not callable: " + e);
        failures++;
      }
    }

    if (failures > 0) {
      System.err.println(
          "astrai18n: unlock anchors moved ("
              + failures
              + " problem(s)) — refusing to build. The agent would load cleanly and silently do"
              + " nothing. Re-check Astrai18nAgent against this Tolgee version.");
      System.exit(1);
    }
    System.out.println("astrai18n: all agent anchors verified");
  }

  private static Class<?> load(String name, ClassLoader cl) {
    try {
      return Class.forName(name, false, cl);
    } catch (ClassNotFoundException | LinkageError e) {
      return null;
    }
  }

  private static boolean hasGet(Class<?> type) {
    for (Method m : type.getDeclaredMethods()) {
      if (m.getName().equals("get")) {
        return true;
      }
    }
    return false;
  }
}
