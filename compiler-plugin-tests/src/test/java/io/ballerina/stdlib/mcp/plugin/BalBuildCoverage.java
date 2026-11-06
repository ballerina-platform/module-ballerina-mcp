/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.stdlib.mcp.plugin;

import java.util.Map;

/**
 * Passes the JaCoCo agent to {@code bal build} subprocesses, which run the compiler plugin outside the test JVM.
 */
public final class BalBuildCoverage {

    private static final String AGENT_PROPERTY = "balBuildJacocoAgent";

    private BalBuildCoverage() {
    }

    public static void attach(ProcessBuilder processBuilder) {
        String agent = System.getProperty(AGENT_PROPERTY);
        if (agent == null || agent.isBlank()) {
            return;
        }
        Map<String, String> env = processBuilder.environment();
        String javaOpts = env.get("JAVA_OPTS");
        env.put("JAVA_OPTS", javaOpts == null || javaOpts.isBlank() ? agent : javaOpts + " " + agent);
    }
}
