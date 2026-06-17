package net.astrateam.astrapdf;

import static net.bytebuddy.matcher.ElementMatchers.named;

import java.lang.instrument.Instrumentation;
import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

/**
 * Forces the application's premium license tier to ENTERPRISE at runtime.
 *
 * <p>The entire license system funnels through a single cached {@code License} enum
 * (NORMAL / SERVER / ENTERPRISE). Most feature gates read it through one of two
 * methods, so instrumenting those unlocks all server/enterprise features
 * (OAuth2/OIDC SSO, external PostgreSQL datasource, audit, backups, ...):
 *
 * <ul>
 *   <li>{@code ...ee.LicenseKeyChecker#getPremiumLicenseEnabledResult()} — the read
 *       accessor every gate (and the boot beans in EEAppConfig) consult.</li>
 *   <li>{@code ...ee.KeygenLicenseVerifier#verifyLicense(String)} — the producer of
 *       the tier. Skipping its body also avoids the outbound keygen.sh validation
 *       HTTP call, so the build runs fully offline / air-gapped.</li>
 * </ul>
 *
 * <p>Both methods return the {@code License} enum, so a single advice — skip the
 * original body, then return {@code License.ENTERPRISE} — applies to both. The
 * advice resolves the enum reflectively via the instrumented class's own
 * classloader, so this agent has no compile-time dependency on the application.
 *
 * <p>Stirling 2.12 added a third, field-reading boot gate
 * {@code LicenseKeyChecker#requireProOrEnterprise(String)} that bypasses the getter
 * above (it reads the cached field, which is only populated when a license key is
 * configured). A separate advice skips that {@code void} method's body so it never
 * throws, keeping premium-only settings (storage.provider=database/s3, cluster S3,
 * ssoAutoLogin) bootable without a license key.
 */
public final class AstraPdfAgent {

    private static final String LICENSE_CHECKER =
            "stirling.software.proprietary.security.configuration.ee.LicenseKeyChecker";
    private static final String LICENSE_VERIFIER =
            "stirling.software.proprietary.security.configuration.ee.KeygenLicenseVerifier";

    private AstraPdfAgent() {}

    public static void premain(String args, Instrumentation inst) {
        install(inst);
    }

    public static void agentmain(String args, Instrumentation inst) {
        install(inst);
    }

    private static void install(Instrumentation inst) {
        // Tolerate class file versions newer than this Byte Buddy release knows
        // about (the runtime image ships a bleeding-edge JDK).
        System.setProperty("net.bytebuddy.experimental", "true");

        new AgentBuilder.Default()
                .disableClassFormatChanges()
                .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                .type(named(LICENSE_CHECKER))
                .transform(
                        (builder, type, loader, module, pd) ->
                                builder.visit(
                                                Advice.to(ForceEnterprise.class)
                                                        .on(named("getPremiumLicenseEnabledResult")))
                                        // 2.12+ added a field-reading boot gate that bypasses the
                                        // getter above; neutralise it so premium-only settings
                                        // (storage.provider=database/s3, cluster S3, ssoAutoLogin)
                                        // never fail fast regardless of the cached license field.
                                        .visit(
                                                Advice.to(AllowAlways.class)
                                                        .on(named("requireProOrEnterprise"))))
                .type(named(LICENSE_VERIFIER))
                .transform(
                        (builder, type, loader, module, pd) ->
                                builder.visit(
                                        Advice.to(ForceEnterprise.class).on(named("verifyLicense"))))
                .installOn(inst);
    }

    /** Skips the original method body and returns {@code License.ENTERPRISE}. */
    public static final class ForceEnterprise {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter() {
            // Returning a non-default value (true) skips the original method body,
            // including any network license validation.
            return true;
        }

        @Advice.OnMethodExit(suppress = Throwable.class)
        public static void exit(
                @Advice.Origin Class<?> origin,
                @Advice.Return(readOnly = false, typing = Assigner.Typing.DYNAMIC) Object returned)
                throws ClassNotFoundException {
            Class<?> licenseEnum =
                    Class.forName(
                            "stirling.software.proprietary.security.configuration.ee."
                                    + "KeygenLicenseVerifier$License",
                            true,
                            origin.getClassLoader());
            @SuppressWarnings({"unchecked", "rawtypes"})
            Object enterprise = Enum.valueOf((Class) licenseEnum, "ENTERPRISE");
            returned = enterprise;
        }
    }

    /**
     * Skips the original method body, returning normally without running it. Used for {@code
     * LicenseKeyChecker#requireProOrEnterprise(String)} (introduced in Stirling 2.12), a {@code
     * void} boot-time gate that throws {@code IllegalStateException} when the cached license field
     * is not Pro/Enterprise. That field bypasses the instrumented {@code
     * getPremiumLicenseEnabledResult()} accessor and is only populated when a license key is
     * configured, so without this the gate would fail fast for premium-only settings even though
     * the tier is forced ENTERPRISE elsewhere. Skipping the body makes the gate a no-op.
     */
    public static final class AllowAlways {

        @Advice.OnMethodEnter(skipOn = Advice.OnNonDefaultValue.class)
        public static boolean enter() {
            // Non-default return (true) skips the original body, so the gate never throws.
            return true;
        }
    }
}
