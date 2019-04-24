part of dherkin_core3;

class Scenario {
  // todo: Fetch this from GherkinVocabulary or something
  String gherkinKeyword = "Scenario";

  String name;

  List<String> tags;

  Scenario background;

  List<Step> steps = [];
  GherkinTable examples = new GherkinTable();

  Location location;

  Scenario(this.name, this.location);

  /// Will execute the background and the scenario.
  /// If this scenario has an example table, it will execute all the generated scenarios,
  /// each with its own background, but background will be added to this scenario's buffer only once.
  Future<ScenarioStatus> execute(
      DherkinState state, DherkinScenarioSession scenarioSession,
      {isFirstOfFeature: true}) async {
    var scenarioStatus = new ScenarioStatus(state.fmt)
      ..scenario = this
      ..background = this.background;

    if (examples._table.isEmpty) {
      examples._table.add({});
    }
    if (!examples.names.isEmpty) {
      state.fmt.examples(examples);
    }
    for (Map example in examples) {
      await _executeSubScenario(scenarioStatus, example, state, scenarioSession,
          isFirstOfFeature: isFirstOfFeature);
    }
    if (!examples.names.isEmpty) {
      state.fmt.examplesEnd();
    }
    return scenarioStatus;
  }

  void addStep(Step step) {
    steps.add(step);
  }

  String toString() {
    return "${tags == null ? "" : tags} $name $steps \nExamples: $examples";
  }

  Future<ScenarioStatus> _executeSubScenario(ScenarioStatus scenarioStatus,
      exampleRow, DherkinState state, DherkinScenarioSession scenarioSession,
      {isFirstOfFeature: true}) async {
    ScenarioStatus backgroundStatus;
    if (background != null) {
      backgroundStatus = await background.execute(state, scenarioSession);
    }
    if (backgroundStatus != null) {
      scenarioStatus.mergeBackground(backgroundStatus,
          isFirst: isFirstOfFeature);
    }

    state.fmt.startOfScenarioLifeCycle(scenarioStatus);

    var iter = steps.iterator;
    while (iter.moveNext()) {
      var step = iter.current;
      var stepStatus = new StepStatus(state.fmt)..step = step;

      var decodedVerbiage = step.decodeVerbiage(exampleRow);

      var found = state.stepRunners.keys.firstWhere(
          (RegExp key) => key.hasMatch(decodedVerbiage),
          orElse: () => null);

      if (found == null) {
        stepStatus.defined = false;
        state.fmt.step(stepStatus);
        scenarioStatus.undefinedSteps.add(stepStatus);
        continue;
      }

      var match = found.firstMatch(decodedVerbiage);

      // (unrelated) Notes :
      // The FeatureContext class approach for stepdefs makes sense :
      // - you implement methods and wrap them with annotations.
      // - you use properties as you want as context shared by steps.

      // Parameters from Regex
      var params = [];
      for (var i = 1; i <= match.groupCount; i++) {
        params.add(Step.unserialize(match.group(i)));
      }
      // PyString
      if (step.pyString != null) {
        params.add(step.pyString);
      }

      Map<String, dynamic> moreParams = {"out": stepStatus.out};

      if (!exampleRow.isEmpty) {
        moreParams["exampleRow"] = exampleRow;
      }

      if (!step.table.empty) {
        moreParams["table"] = step.table;
      }

      try {
        // to actually run the step
        await state.stepRunners[found](params, moreParams, scenarioSession);
      } catch (e, s) {
        _log.fine("Step failed: $step");
        var failure = new StepFailure();
        if (e is Exception) {
          failure.error = e;
        } else {
          failure.error = new Exception(e.toString());
        }
        failure.trace = s.toString();
        stepStatus.failure = failure;
        scenarioStatus.failedSteps.add(stepStatus);
      } finally {
        if (!stepStatus.failed) {
          scenarioStatus.passedSteps.add(stepStatus);
        }
        state.fmt.step(stepStatus);
      }
    }

    state.fmt.endOfScenarioLifeCycle(scenarioStatus);

    return scenarioStatus;
  }
}
