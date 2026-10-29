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

package io.ballerina.stdlib.mcp.plugin.v2;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import io.ballerina.compiler.syntax.tree.FunctionCallExpressionNode;
import io.ballerina.compiler.syntax.tree.NodeVisitor;
import io.ballerina.projects.BuildOptions;
import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.Module;
import io.ballerina.projects.Package;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.BuildProject;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.swagger.v3.core.util.Json;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Tests for the MCP compiler plugin diagnostics on '@http:Header' and 'http:Headers' tool parameters.
 */
public class CompilerPluginTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "ballerina_sources", "v2")
            .toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get("../", "target", "ballerina-runtime")
            .toAbsolutePath();
    // Resolving a submodule import otherwise asks Central for the package name.
    private static final BuildOptions OFFLINE = BuildOptions.builder().setOffline(true).build();

    private static final String MCP_202 = "MCP_202";
    private static final String MCP_204 = "MCP_204";
    private static final String MCP_207 = "MCP_207";
    private static final String MCP_208 = "MCP_208";
    private static final String MCP_210 = "MCP_210";
    private static final String MCP_211 = "MCP_211";
    private static final String MCP_212 = "MCP_212";
    private static final String MCP_213 = "MCP_213";

    private Package loadPackage(String path) {
        Path projectDirPath = RESOURCE_DIRECTORY.resolve(path);
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), projectDirPath, OFFLINE);
        return project.currentPackage();
    }

    private static ProjectEnvironmentBuilder getEnvironmentBuilder() {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        return ProjectEnvironmentBuilder.getBuilder(environment);
    }

    private DiagnosticResult compile(String path) {
        Package currentPackage = loadPackage(path);
        // The MCP compiler plugin is registered as a CodeModifier, so its diagnostics are
        // reported by the code-generate/modify phase, not by getCompilation() alone
        return currentPackage.runCodeGenAndModifyPlugins();
    }

    private long errorCount(DiagnosticResult diagnosticResult) {
        return diagnosticResult.diagnostics().stream()
                .filter(d -> d.diagnosticInfo().severity().equals(DiagnosticSeverity.ERROR)).count();
    }

    private void assertError(DiagnosticResult diagnosticResult, int index, String messagePart, String code) {
        Diagnostic diagnostic = (Diagnostic) diagnosticResult.errors().toArray()[index];
        Assert.assertTrue(diagnostic.message().contains(messagePart),
                "expected message containing '" + messagePart + "' but found: " + diagnostic.message());
        Assert.assertEquals(diagnostic.diagnosticInfo().code(), code);
    }

    @Test
    public void testValidHeaderParameterTypes() {
        DiagnosticResult diagnosticResult = compile("sample_package_1");
        Assert.assertEquals(errorCount(diagnosticResult), 0,
                "valid header parameter shapes must not produce errors: "
                        + diagnosticResult.errors().toString());
    }

    @Test
    public void testInvalidUnionHeaderParamType() {
        DiagnosticResult diagnosticResult = compile("sample_package_2");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Invalid type of header param 'mixed'", MCP_208);
    }

    @Test
    public void testHeaderRecordWithRestFields() {
        DiagnosticResult diagnosticResult = compile("sample_package_3");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Invalid type of header param 'hdrs'", MCP_208);
    }

    @Test
    public void testDuplicateHttpHeadersParams() {
        DiagnosticResult diagnosticResult = compile("sample_package_4");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Duplicate parameter 'second'", MCP_207);
        assertError(diagnosticResult, 0, "type 'http:Headers'", MCP_207);
    }

    @Test
    public void testInvalidHeaderParamType() {
        DiagnosticResult diagnosticResult = compile("sample_package_5");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Invalid type of header param 'payload'", MCP_208);
    }

    @Test
    public void testSessionParamStatelessViaTransportConfig() {
        DiagnosticResult diagnosticResult = compile("sample_package_7");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "is not allowed when sessionMode is 'STATELESS'", MCP_204);
    }

    @Test
    public void testSessionParamAtAnyPosition() {
        DiagnosticResult diagnosticResult = compile("session_param_any_position");
        Assert.assertEquals(errorCount(diagnosticResult), 0, diagnosticResult.errors().toString());
    }

    @Test
    public void testDuplicateSessionParams() {
        DiagnosticResult diagnosticResult = compile("duplicate_session_param");
        Assert.assertEquals(errorCount(diagnosticResult), 1, diagnosticResult.errors().toString());
        assertError(diagnosticResult, 0, "Duplicate parameter 'second'", MCP_207);
        assertError(diagnosticResult, 0, "type 'mcp:HttpSession'", MCP_207);
    }

    @Test
    public void testDuplicateHttpRequestParams() {
        DiagnosticResult diagnosticResult = compile("sample_package_10");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Duplicate parameter 'second'", MCP_207);
        assertError(diagnosticResult, 0, "type 'http:Request'", MCP_207);
    }

    @Test
    public void testValidAdvancedService() {
        DiagnosticResult diagnosticResult = compile("sample_package_11");
        Assert.assertEquals(errorCount(diagnosticResult), 0,
                "valid advanced service shapes must not produce errors: "
                        + diagnosticResult.errors().toString());
    }

    @Test
    public void testAdvancedServiceMissingOnCallTool() {
        DiagnosticResult diagnosticResult = compile("sample_package_12");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "must define a remote method 'onCallTool'", MCP_210);
    }

    @Test
    public void testAdvancedOnCallToolMissingCallToolParams() {
        DiagnosticResult diagnosticResult = compile("sample_package_13");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "must declare exactly one parameter of type 'mcp:CallToolParams'", MCP_211);
    }

    @Test
    public void testAdvancedUnsupportedParam() {
        DiagnosticResult diagnosticResult = compile("sample_package_14");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0, "Parameter 'extra' in function 'onCallTool' has an unsupported type",
                MCP_202);
    }

    @Test
    public void testAdvancedInvalidReturnType() {
        DiagnosticResult diagnosticResult = compile("sample_package_15");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0,
                "must return 'mcp:CallToolResult|mcp:InputRequiredResult|mcp:ServerError'",
                MCP_212);
    }

    @Test
    public void testAdvancedUnknownRemoteMethod() {
        DiagnosticResult diagnosticResult = compile("sample_package_16");
        Assert.assertEquals(errorCount(diagnosticResult), 2);
        assertError(diagnosticResult, 0, "Remote method 'doSomething' is not supported", MCP_213);
        assertError(diagnosticResult, 0, "Only 'onListTools' and 'onCallTool' are allowed", MCP_213);
        assertError(diagnosticResult, 1, "Remote method 'onSubscribe' is not supported", MCP_213);
    }

    @Test
    public void testAdvancedListToolsUnsupportedParam() {
        DiagnosticResult diagnosticResult = compile("sample_package_17");
        Assert.assertEquals(errorCount(diagnosticResult), 1);
        assertError(diagnosticResult, 0,
                "Parameter 'params' in function 'onListTools' has an unsupported type", MCP_202);
        // The supported-types message for 'onListTools' must not advertise the 'onCallTool'-only types.
        Diagnostic diagnostic = (Diagnostic) diagnosticResult.errors().toArray()[0];
        Assert.assertFalse(diagnostic.message().contains("mcp:CallToolParams"),
                "onListTools supported-types message must not list 'mcp:CallToolParams': " + diagnostic.message());
        Assert.assertFalse(diagnostic.message().contains("mcp:HttpSession"),
                "onListTools supported-types message must not list 'mcp:HttpSession': " + diagnostic.message());
    }

    @Test
    public void testMetaParameterCanAppearBeforeDataParameters() {
        DiagnosticResult diagnosticResult = compile("sample_package_18");
        Assert.assertEquals(errorCount(diagnosticResult), 0,
                "an optional mcp:RequestMeta parameter must be accepted outside the final position: "
                        + diagnosticResult.errors().toString());
    }

    @Test
    public void testRequestMetaParameterMustBeOptional() {
        DiagnosticResult diagnosticResult = compile("required_request_meta");
        Assert.assertEquals(errorCount(diagnosticResult), 1, diagnosticResult.errors().toString());
        assertError(diagnosticResult, 0, "(e.g., 'mcp:RequestMeta?')", "MCP_206");
    }

    @Test
    public void testProtocolSessionDiagnostics() {
        String[] codes = {"MCP_WARNING_202", "MCP_214", "MCP_WARNING_204", "MCP_WARNING_203"};
        for (int index = 0; index < codes.length; index++) {
            DiagnosticResult result = compile("sample_package_" + (19 + index));
            String code = codes[index];
            Assert.assertTrue(result.diagnostics().stream().anyMatch(d -> d.diagnosticInfo().code().equals(code)),
                    "Expected " + code + ": " + result.diagnostics());
            Assert.assertEquals(errorCount(result), index == 1 ? 1L : 0L);
        }
        DiagnosticResult legacy = compile("sample_package_23");
        Assert.assertEquals(errorCount(legacy), 0L);
        Assert.assertFalse(legacy.diagnostics().stream()
                .anyMatch(d -> d.diagnosticInfo().code().startsWith("MCP_WARNING_20")));
    }
    @Test
    public void testOptionalSessionAliasInModernStatelessService() {
        DiagnosticResult result = compile("sample_package_24");
        Assert.assertEquals(errorCount(result), 0L);
        Assert.assertEquals(result.diagnostics().stream()
                .filter(d -> d.diagnosticInfo().code().equals("MCP_WARNING_203")).count(), 1L);
    }

    @Test
    public void testModernResultsOnExistingAdvancedService() {
        DiagnosticResult result = compile("sample_package_25");
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());
    }

    @Test
    public void testAdvancedHandlersBindHttpValuesAndCursor() {
        DiagnosticResult result = compile("advanced_handler_http_parameters");
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());
    }

    @Test
    public void testAdvancedHandlerUnsupportedParameters() {
        DiagnosticResult result = compile("advanced_handler_unsupported_parameters");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "Parameter 'cursor' in function 'onListTools' has an unsupported type", MCP_202);
    }

    @Test
    public void testMcpArgumentHeaderAnnotation() {
        DiagnosticResult result = compile("sample_package_26");
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());
    }

    @Test
    public void testMcpArgumentHeaderDiagnostics() {
        DiagnosticResult invalidType = compile("sample_package_27");
        Assert.assertEquals(errorCount(invalidType), 1L);
        assertError(invalidType, 0, "cannot use '@mcp:Argument'", "MCP_215");

        DiagnosticResult numberTypes = compile("argument_number_headers");
        Assert.assertEquals(errorCount(numberTypes), 2L, numberTypes.errors().toString());
        assertError(numberTypes, 0, "cannot use '@mcp:Argument'", "MCP_215");
        assertError(numberTypes, 1, "cannot use '@mcp:Argument'", "MCP_215");

        DiagnosticResult invalidName = compile("sample_package_28");
        Assert.assertEquals(errorCount(invalidName), 1L);
        assertError(invalidName, 0, "Invalid MCP argument header name 'Bad Header'", "MCP_216");

        DiagnosticResult duplicateName = compile("sample_package_29");
        Assert.assertEquals(errorCount(duplicateName), 1L);
        assertError(duplicateName, 0, "Duplicate MCP argument header name 'region'", "MCP_217");

        DiagnosticResult explicitSchema = compile("sample_package_30");
        Assert.assertEquals(errorCount(explicitSchema), 1L);
        assertError(explicitSchema, 0, "cannot combine '@mcp:Argument'", "MCP_218");

        DiagnosticResult conflictingBinding = compile("sample_package_31");
        Assert.assertEquals(errorCount(conflictingBinding), 1L);
        assertError(conflictingBinding, 0, "cannot use '@mcp:Argument'", "MCP_215");
    }

    @Test
    public void testUnstructuredOutputWithExplicitOutputSchema() {
        DiagnosticResult result = compile("unstructured_output_with_output_schema");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "cannot combine 'structuredOutput: false'", "MCP_221");
    }

    @Test
    public void testUnstructuredOutputSkipsReturnSchemaGeneration() {
        DiagnosticResult result = compile("unstructured_unmappable_return");
        Assert.assertEquals(result.diagnostics().size(), 0, result.diagnostics().toString());
    }

    @Test
    public void testUnmappableParameterNeedsExplicitSchema() {
        DiagnosticResult result = compile("recursive_parameter");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "Failed to generate the input schema for the function 'count'. "
                + "Supply it with the 'schema' field of '@mcp:Tool'.", "MCP_201");
    }

    @Test
    public void testUnmappableReturnTypesStayUnstructured() {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(),
                RESOURCE_DIRECTORY.resolve("unmappable_return_types"), OFFLINE);
        DiagnosticResult result = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(result.diagnostics().size(), 0, result.diagnostics().toString());

        Module module = project.currentPackage().getDefaultModule();
        String source = module.documentIds().stream()
                .map(documentId -> module.document(documentId).syntaxTree().toSourceCode())
                .collect(Collectors.joining());
        Assert.assertTrue(source.contains("outputSchema:{\"type\":\"string\"}"), source);
        Assert.assertEquals(source.split("outputSchema:\\{", -1).length - 1, 1, source);
    }

    @Test
    public void testLegacyModeIgnoresUnusedStructuredOutputRequirement() {
        DiagnosticResult result = compile("legacy_structured_output");
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());
    }

    @Test
    public void testNamedConstantStructuredOutputRequiresSchema() {
        DiagnosticResult result = compile("constant_structured_output");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "Failed to generate the output schema", "MCP_222");
    }

    @Test
    public void testRequiredStructuredOutputRejectsNilOnlyResult() {
        DiagnosticResult result = compile("nil_required_structured_output");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "Failed to generate the output schema", "MCP_222");
    }

    @Test
    public void testConstantDisabledOutputRejectsSuppliedSchema() {
        DiagnosticResult result = compile("constant_disabled_output");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "cannot combine 'structuredOutput: false'", "MCP_221");
    }

    @Test
    public void testStaticStructuredOutputFormsRequireSchema() {
        DiagnosticResult result = compile("static_policy_forms");
        Assert.assertEquals(errorCount(result), 3L, result.diagnostics().toString());
        for (int index = 0; index < 3; index++) {
            assertError(result, index, "Failed to generate the output schema", "MCP_222");
        }
    }

    @Test
    public void testRuntimeConfigurationRecordsDeferPolicyValidation() {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(),
                RESOURCE_DIRECTORY.resolve("runtime_policy_records"), OFFLINE);
        DiagnosticResult result = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());
        DiagnosticResult compilation = project.currentPackage().getCompilation().diagnosticResult();
        Assert.assertEquals(compilation.errorCount(), 0, compilation.diagnostics().toString());
    }

    @Test
    public void testDynamicBasicServiceChecksKnownRequiredPolicy() {
        DiagnosticResult result = compile("dynamic_required_output");
        Assert.assertEquals(errorCount(result), 3L, result.diagnostics().toString());
        for (int index = 0; index < 3; index++) {
            assertError(result, index, "Failed to generate the output schema", "MCP_222");
        }
    }

    @Test
    public void testExplicitStructuredOutputRequiresReturnSchema() {
        DiagnosticResult result = compile("unmappable_return_structured_output");
        Assert.assertEquals(errorCount(result), 1L, result.diagnostics().toString());
        assertError(result, 0, "Failed to generate the output schema for the function 'retAny'", "MCP_222");
    }

    @Test
    public void testContextAndInputRequiredResultStayOutOfToolSchemas() {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), RESOURCE_DIRECTORY.resolve("sample_package_32"),
                OFFLINE);
        DiagnosticResult result = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());

        Module module = project.currentPackage().getDefaultModule();
        String source = module.documentIds().stream()
                .map(documentId -> module.document(documentId).syntaxTree().toSourceCode())
                .collect(Collectors.joining());
        Assert.assertTrue(source.contains("\"required\":[\"path\"]"), source);
        Assert.assertFalse(source.contains("\"context\""), source);
        Assert.assertTrue(source.contains("outputSchema:{\"type\":\"string\"}"), source);
    }

    @Test
    public void testRecordTypeFormSchema() throws JsonProcessingException {
        BuildProject project = BuildProject.load(getEnvironmentBuilder(), RESOURCE_DIRECTORY.resolve("sample_package_33"),
                OFFLINE);
        DiagnosticResult result = project.currentPackage().runCodeGenAndModifyPlugins();
        Assert.assertEquals(errorCount(result), 0L, result.diagnostics().toString());

        JsonNode expected = Json.mapper().readTree("""
                {"type": "object",
                 "properties": {
                   "name": {"type": "string", "description": "The guest's name"},
                   "guests": {"type": "integer", "description": "How many people are coming"},
                   "outdoor": {"type": "boolean", "description": "Whether to sit outside"},
                   "area": {"type": "string", "description": "The seating area", "enum": ["indoor", "patio"]},
                   "diets": {"type": "array", "description": "Dietary needs",
                             "items": {"type": "string", "enum": ["vegan", "gluten-free"]}},
                   "deposit": {"type": "number", "description": "The deposit to hold"}},
                 "required": ["name", "guests", "area", "diets", "deposit"]}""");
        Assert.assertEquals(Json.mapper().readTree(elicitFormSchemaArgument(project)), expected);
        DiagnosticResult compilation = project.currentPackage().getCompilation().diagnosticResult();
        Assert.assertEquals(compilation.errorCount(), 0, compilation.errors().toString());
    }

    @Test
    public void testUnsupportedFormFieldTypes() {
        DiagnosticResult result = compile("sample_package_34");
        Assert.assertEquals(errorCount(result), 4L, result.diagnostics().toString());
        assertError(result, 0, "Field 'address' of record type 'Shipping'", "MCP_219");
        assertError(result, 1, "Field 'details' of record type 'Note'", "MCP_219");
        assertError(result, 2, "Field 'stops' of record type 'Delivery'", "MCP_219");
        assertError(result, 3, "Field 'phone' of record type 'Contact'", "MCP_219");
    }

    @Test
    public void testFormSchemaTypeMustBeStaticRecordType() {
        DiagnosticResult result = compile("sample_package_35");
        Assert.assertEquals(errorCount(result), 3L, result.diagnostics().toString());
        assertError(result, 0, "must be a form schema value or a named record type", "MCP_220");
        assertError(result, 1, "must be a form schema value or a named record type", "MCP_220");
        assertError(result, 2, "must be a form schema value or a named record type", "MCP_220");
    }

    private static String elicitFormSchemaArgument(BuildProject project) {
        Module module = project.currentPackage().getDefaultModule();
        List<String> arguments = new ArrayList<>();
        NodeVisitor visitor = new NodeVisitor() {
            @Override
            public void visit(FunctionCallExpressionNode call) {
                if (call.functionName().toSourceCode().trim().equals("mcp:elicitForm")) {
                    arguments.add(call.arguments().get(1).toSourceCode().trim());
                }
                super.visit(call);
            }
        };
        module.documentIds().forEach(id -> module.document(id).syntaxTree().rootNode().accept(visitor));
        Assert.assertEquals(arguments.size(), 1, arguments.toString());
        return arguments.get(0);
    }
}
