package net.astrateam.astrai18n;

import static net.bytebuddy.matcher.ElementMatchers.named;

import java.lang.instrument.Instrumentation;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

/**
 * Runtime agent that configures the platform's active feature set.
 *
 * <p>The set of active features is produced by a single bean implementing
 * {@code io.tolgee.component.enabledFeaturesProvider.EnabledFeaturesProvider}, whose
 * {@code get(Long): Feature[]} is the one method both the backend and the web UI read to
 * decide which features are available. This agent instruments that method so it returns the
 * complete {@code Feature} enum, configuring the instance to run with the full feature set.
 *
 * <p>Whichever concrete implementation is present in the image is instrumented:
 *
 * <ul>
 *   <li>{@code io.tolgee.ee.component.PublicEnabledFeaturesProvider} — the {@code @Primary} bean.</li>
 *   <li>{@code io.tolgee.component.enabledFeaturesProvider.EnabledFeaturesProviderOssImpl} — the
 *       fallback that otherwise returns an empty array.</li>
 * </ul>
 *
 * <p>A single advice applies to both: skip the original {@code get} body and return
 * {@code Feature.values()}. The {@code Feature} enum is resolved reflectively via the instrumented
 * class's own classloader, so this agent carries no compile-time dependency on the application and
 * is independent of the application version. No external endpoints are contacted: the provider's
 * periodic remote refresh short-circuits when no key is configured, so the instance runs offline.
 */
public final class Astrai18nAgent {

  private static final String PUBLIC_PROVIDER =
      "io.tolgee.ee.component.PublicEnabledFeaturesProvider";
  private static final String OSS_PROVIDER =
      "io.tolgee.component.enabledFeaturesProvider.EnabledFeaturesProviderOssImpl";

  private Astrai18nAgent() {}

  public static void premain(String args, Instrumentation inst) {
    install(inst);
  }

  public static void agentmain(String args, Instrumentation inst) {
    install(inst);
  }

  private static void install(Instrumentation inst) {
    // Tolerate class file versions newer than this Byte Buddy release knows about
    // (the runtime JDK may move ahead of the bundled Byte Buddy).
    System.setProperty("net.bytebuddy.experimental", "true");

    new AgentBuilder.Default()
        .disableClassFormatChanges()
        .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
        .type(named(PUBLIC_PROVIDER).or(named(OSS_PROVIDER)))
        .transform(
            (builder, type, loader, module, pd) ->
                builder.visit(Advice.to(FullFeatureSet.class).on(named("get"))))
        .installOn(inst);
  }

  /** Skips the original {@code get} body and returns the complete {@code Feature[]} enum. */
  public static final class FullFeatureSet {

    @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
    public static boolean enter() {
      // A non-default return (true) skips the original body, including the provider's
      // subscription lookup and any associated remote call.
      return true;
    }

    @Advice.OnMethodExit(suppress = Throwable.class)
    public static void exit(
        @Advice.Origin Class<?> origin,
        @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned)
        throws Exception {
      Class<?> feature =
          Class.forName("io.tolgee.constants.Feature", true, origin.getClassLoader());
      returned = feature.getMethod("values").invoke(null);
    }
  }
}
