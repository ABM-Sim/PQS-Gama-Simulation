/**
* Name:    bdi-hierarchy-reworked
* Author:  Dario Dubberstein, Friedrich-Schiller-University Jena
* Tags:    bdi, agent-based model, innovation diffusion, post-quantum cryptography, SME
* Platform: GAMA 2025.6.4
*
* Agent-based model of the diffusion of post-quantum-safe encryption across a heterogeneous market
* of organisations (enterprise, enterprise_medium, business_small, startup_it). Each organisation is
* a BDI agent that repeatedly decides between adopting, investing in improvements, or waiting,
* based on the weighted desire-to-adopt formula (Eq. 5) of the underlying concept (Schindler and
* Dubberstein 2023). Market pressure (pre_mar) is a shared, self-reinforcing signal fed by every
* adopter, weighted by network outdegree.
*
* Repository: https://github.com/ABM-Sim/PQS-Gama-Simulation
*
* Equation numbering: comments in this file use the concept's equation numbers
* (Schindler and Dubberstein 2023); the accompanying paper renumbers them as follows:
*   concept Eq.33 inertia       = paper Eq. 1
*   concept Eq.34 in_res        = paper Eq. 2
*   concept Eq.35 funds         = paper Eq. 3
*   prob_cost                   = paper Eq. 4
*   concept Eq.38 desire_adopt  = paper Eq. 5
*   concept Eq.7  pre_mar       (extended here: weighted by adopters' outdegree, see org)
*
* ===================================================================================
* OUTPUT FILES (per experiment, prefixed with model_version)
* ===================================================================================
*   <name>.csv                   periodic trajectory log (every trajectory_log_interval cycles)
*   <name>_milestones.csv        write-once log: cycle at which 5/10/20/35/50/60/75/80/90/95/97/99/
*                                100 % of the population first adopted
*   <name>_group_milestones.csv  same checkpoints, computed separately for SMEs (business_small +
*                                startup_it) and large organisations (enterprise +
*                                enterprise_medium)
*   <name>_finecurve.csv         write-once log: first cycle for every 1 % adoption step (0-100)
*
* Completion times must be read from the write-once milestone files, NOT from the last row of
* the periodic trajectory log: in batch mode GAMA does not always halt a replicate promptly once
* its `until:` condition is met, so the trajectory log can continue past true completion.
*
* Note on the fine-curve file: the list column is written unquoted, so a CSV reader splits it on
* its internal commas. Parse each row with line.split(',', 5) and evaluate the last field as a list.
*
* ===================================================================================
* RECOMMENDED GAMA SETTINGS
* ===================================================================================
*   Preferences > Parallelism:
*     "Allow experiments to run simulations in parallel"             = Yes
*     "In batch, allow to run simulations with all available processors" = No
*   Very long single headless sessions (> ~12 h) have produced native JVM crashes; split large
*   suites into several XML plans instead of one continuous run.
*
* ===================================================================================
* VERSION HISTORY
* ===================================================================================
* v1.0  Performance rework: deduplicated placement logic, deferred CSV writes, replaced looped
*       GUI "batch" runs with native `type: batch` experiments. Scenario 1-5 scaffolds added.
* v1.1  Formula audit against the concept's equations. Fixed: copy-paste error in market status
*       tracking (adopt_status_startup_it never updated); missing default for inert_pressure;
*       self-referential initialisers in the base org species. Restored independently weighted
*       desire_adopt (Eq. 5) and inertia (Eq. 1), which had been collapsed into a single shared
*       "pressure" weight. Added the missing fin_matching term (Eq. 3).
* v1.2  `organisations` derived from the per-type counts; base `org` can no longer be
*       instantiated. Social-pressure computation decoupled from link visualisation so that
*       pre_mar is computed in batch mode.
* v1.3  Nested ternaries replaced with explicit if/else. Scenario 6 (weight sensitivity) and
*       Scenario 7 (government x top-down/bottom-up) added.
* v1.4  Batch suite right-sized (removed unintended full-factorial blow-ups). Scenario 6 split
*       into one-factor-at-a-time experiments 6A-6I. "Agent count scale" changed from min/max to
*       init so it is held fixed instead of being swept.
* v1.5  Fixed invalid `get_liking()` call (now `tempDestination.liking`) and invalid `save`
*       facets; replaced per-experiment saves with a shared log_trajectory reflex and a single
*       column schema for all scenarios.
* v1.6-v1.9  Crash "Distribution elements should not be all equal to 0". Root cause (confirmed
*       in SimpleBdiArchitecture.java): with probabilistic_choice = true, obligation selection
*       runs over declared norms only; this model declares none, so an empty list is passed to
*       Random.opRndChoice every cycle. Fixed by probabilistic_choice <- false. Also added an
*       explicit strength to add_desire(overcome_inertia).
* v2.0  Weighted-random decision making re-implemented explicitly with rnd_choice() inside
*       check_inertia, idling and improve_odds, independent of the engine's norm/obligation path.
* v2.1  rnd_choice requires strictly positive weights; improvement weights of the form 1 - x
*       become negative once x grows past 1. All weights floored (max(0.01, ...)); desire weights
*       floored at 0.001 as a safety margin.
* v2.2  min:/max:/step: batch parameters did not produce the intended levels; all replaced by
*       explicit `among:` lists.
* v2.3  model_version added as filename prefix and CSV column.
* v2.4  Removed `do pause;` from end_simulation: in batch mode it pauses the experiment scheduler
*       and truncates sibling replicates. The hard-coded 210-cycle cap (a workaround for the same
*       problem) replaced by max_cycle_safety_cap (default 5000), a runaway guard only.
* v2.5  CSV headers: every replicate writes its own header at cycle 0 (duplicate header rows in
*       combined files are filtered during analysis). Rewrote the `socialize liking:` distance
*       computation as plain arithmetic to avoid an intermittent ClassCastException in
*       point()/distance_to.
* v2.6-v2.11  Investigation of apparent within-batch drift (completion time correlated with
*       replicate creation order). Changes made during this investigation that remain in place:
*       population aggregates (degree_of_market_pressure, sum_outdegree, finished_adopting) are
*       recomputed each cycle instead of accumulated incrementally; `parallel: false` on all
*       perceive blocks and population-wide ask blocks; experiments restructured to one fixed
*       parameter combination per experiment; replicate_index added as a logged column;
*       population doubled to 60 agents (agent_count_scale = 2). The actual cause was identified
*       in v2.12 as a measurement artefact.
* v2.12 Write-once milestone log added. Comparing it with the trajectory log showed the drift was
*       a measurement artefact: replicates kept running (and logging unchanged rows) after
*       reaching full adoption, by an amount that grows with the replicate's position in the
*       batch. All completion times are taken from the milestone log from this version on.
* v2.13 SME vs. large-organisation group milestone log added.
* v2.14 Fixed "MetaPopulation cannot be cast to ISpecies": the species union is now assigned to a
*       typed list<org> before applying `where`.
* v2.15 Replicate counts sized per scenario (S1: 300; S2-S5, S7: 100 per combination; S6: 150 per
*       level).
* v2.16 1 %-resolution diffusion-curve log added (Scenario 1B).
* v2.17 Fixed "Boolean cannot be cast to IExpression": threshold lists are now built with a plain
*       loop/add in init instead of a collect/range declaration.
* v2.18 Eq. 5 constant exposed as desire_adopt_constant.
* v2.19 Scenario 1C: constant sweep (1.5 / 1.75 / 2.0 / 3.0 / 3.5 / 4.0), motivated by a Monte
*       Carlo estimate of the cycle-0 sigmoid argument (mean approx. 1.7, sd approx. 1.27).
* v2.20 starting_inertia and randomize_starting_inertia added; Scenario 1D (fixed values).
* v2.21 Scenario 1D extended (7-15) and Scenario 1E (random per-agent inertia) added.
* v2.22 Type-differentiated starting inertia (starting_inertia_large / starting_inertia_sme,
*       differentiate_inertia_by_type); Scenario 1F tests two competing hypotheses
*       (bureaucracy: large organisations slower; resource buffer: SMEs slower).
* v2.23 Single government actor. gov_fin and gov_leg are no longer independent rnd(-1,1) draws but
*       a blend of a shared government signal and individual variation:
*         gov_x = tie * multiplier_x * signal_x + (1 - tie) * rnd(-1,1)
*       with signal_fin = gov_subsidy_amount and signal_leg = legal_stringency (new global,
*       default 0, so baseline behaviour is unchanged). Fixed per-type values:
*         enterprise         tie 0.7, legal 1.0 (NIS2 essential), financial 0.6
*         enterprise_medium  tie 0.8, legal 0.7 (NIS2 important), financial 0.8
*         business_small     tie 0.4, legal 0.3 (below NIS2 threshold), financial 1.2
*         startup_it         tie 0.4, legal 0.3, financial 1.2
*       Rationale: Triple Helix proximity (Etzkowitz and Leydesdorff 2000), NIS2 tiering, and
*       evidence that subsidies are more effective for small firms. legal_stringency mirrors
*       gov_subsidy_amount in all Scenario 3 and 7 experiments. Scenario 1G added as a check.
* v2.24 Diagnostic columns added to the trajectory log (current_pre_mar, sum_outdegree,
*       degree_of_market_pressure, per-group adoption counts); Scenario 1H logs every cycle.
* v2.25 Default desire_adopt_constant changed from 1.5 (concept specification) to 3.0. Scenario 1C
*       keeps its explicit values for comparison.
*       Improvement mechanism revised: three mutually exclusive options are kept (improve_know
*       buys external knowledge and raises in_know and cost by the same amount; improve_man /
*       improve_emp raise the factor and in_know, with cost rising by half that amount); all
*       magnitudes halved; the absorption period shortened to one idle cycle (status <- 4),
*       giving the sequence decide, apply, idle, decide.
* v2.26 Scenario 1 run with explicit rng <- "mersenne" to test whether the engine's default
*       generator caused inconsistent results between repeated runs. It did not; see v2.28.
* v2.27 rng <- "mersenne" applied to all experiments (kept for explicit reproducibility).
* v2.28 Repeated large-sample runs of the identical baseline gave opposite-sign SME-large gaps,
*       with replicates inside each run agreeing strongly on direction. Ruled out: RNG engine
*       (v2.26) and independent-launch vs. continuous-session execution. Explanation: pre_mar is a
*       shared, self-reinforcing signal by design (fear of missing out / fear of losing
*       customers), so a small early advantage can tip the population (increasing returns,
*       Arthur 1989), and a single pooled mean is not a stable estimate. Scenario 1I added: 20
*       independent baseline invocations (repeat: 30 each) to estimate the distribution of
*       outcomes instead of one pooled value.
*
* Known, non-functional leftovers:
*   - The two `rule belief: adopt/idle ...` declarations in org never fire: no belief named
*     adopt or idle is ever added. The decision is made by rnd_choice in check_inertia/idling.
* ===================================================================================
*/


model bdi_base_rnd

global {
	/*
	 * Generated couple of shapefiles which include for the testing purpose random assigned dots, 
	 * the amount is noted behind the file assignment and maximum that amount of agents can be assigned for that shapefile
	 * Agents will be placed on these dots so that they each have a unique position
	 * Can later be replaced with a graph if needed.
	 * 
	 */
	
	//file shapefile_dot <- file("../includes/35_dots/35_dots.shp");					// 35
	//file shapefile_dot <- file("../includes/7_dot.shp.shp"); 							// 7 agents
	//file shapefile_dot <- file("../includes/10-Points/entities.shp"); 					// 10 agents	
	//file shapefile_dot <- file("../includes/11-Points/entities.shp"); 				// 11 agents
	//file shapefile_dot <- file("../includes/13-Points/entities.shp"); 				// 13 agents
	//file shapefile_dot <- file("../includes/35-Points/entities.shp"); 				// 35 agents
	file shapefile_dot <- file("../includes/100-Points/entities.shp"); 				// 100 agents

	// Embedded directly in every result filename (see trajectory_output_path assignments below) so a
	// CSV always self-documents which model version produced it -- update this on every version bump.
	string model_version <- "v2.28";

	/*
	 * Runaway guard only. funds grows without bound, so every simulation converges to full
	 * adoption on its own; this cap is set high enough not to be reached in practice and only
	 * stops a broken parameter combination from running indefinitely. (Replaces a former
	 * hard-coded 210-cycle limit.)
	 */
	int max_cycle_safety_cap <- 5000;

    /*
     * "organisations" is now DERIVED from the four typed sub-populations rather than an
     * independent target -- every agent created always gets a real type (enterprise/medium/
     * small/startup). This removes the base `org` species as a live agent entirely (it remains
     * only as an abstract parent for shared BDI logic/plans) and closes off the whole class of
     * "organisations != sum(nb_*)" bugs by construction instead of by convention.
     * To vary total agent count in a batch (e.g. for a performance/robustness sweep), scale
     * `agent_count_scale` rather than setting organisations directly.
     */
    int base_nb_enterprise <- 6;														// black
    int base_nb_enterprise_medium <- 8;												// blue
    int base_nb_business_small <- 8;													// green
    int base_nb_startup_it <- 8;														// red
    int agent_count_scale <- 2;														// multiplies all four base_nb_* proportionally --
    																				// doubled from 1 (v2.9): runs are fast enough
    																				// (~10min for a 360-sim batch) to afford 60
    																				// agents instead of 30 as the new default.

    int nb_enterprise <- base_nb_enterprise * agent_count_scale;
    int nb_enterprise_medium <- base_nb_enterprise_medium * agent_count_scale;
    int nb_business_small <- base_nb_business_small * agent_count_scale;
    int nb_startup_it <- base_nb_startup_it * agent_count_scale;
    int organisations <- nb_enterprise + nb_enterprise_medium + nb_business_small + nb_startup_it;
    
    /*
     * DIFFUSION MILESTONES (v2.12). Standard diffusion-curve checkpoints, not just
     * time-to-100%: 5/10/20/35/50/60/75/80/90/95/97/99/100 percent of organisations adopted.
     * Allows effects on early, median and late adopters to be distinguished (e.g. an
     * intervention that speeds up the 50% milestone while slowing the 100% milestone).
     * Thresholds use ceil() so e.g. 5% of 60 agents requires >=3 adopted, not >=2.99.
     * Recomputed from `organisations`, so these stay correct if agent_count_scale changes.
     */
    int threshold_5pct <- int(ceil(organisations * 0.05));
    int threshold_10pct <- int(ceil(organisations * 0.10));
    int threshold_20pct <- int(ceil(organisations * 0.20));
    int threshold_35pct <- int(ceil(organisations * 0.35));
    int threshold_50pct <- int(ceil(organisations * 0.50));
    int threshold_60pct <- int(ceil(organisations * 0.60));
    int threshold_75pct <- int(ceil(organisations * 0.75));
    int threshold_80pct <- int(ceil(organisations * 0.80));
    int threshold_90pct <- int(ceil(organisations * 0.90));
    int threshold_95pct <- int(ceil(organisations * 0.95));
    int threshold_97pct <- int(ceil(organisations * 0.97));
    int threshold_99pct <- int(ceil(organisations * 0.99));
    // 100% threshold is just `organisations` itself, no separate variable needed.

    // Cycle at which each milestone was first reached; -1 = not yet reached.
    int cycle_5pct <- -1;
    int cycle_10pct <- -1;
    int cycle_20pct <- -1;
    int cycle_35pct <- -1;
    int cycle_50pct <- -1;
    int cycle_60pct <- -1;
    int cycle_75pct <- -1;
    int cycle_80pct <- -1;
    int cycle_90pct <- -1;
    int cycle_95pct <- -1;
    int cycle_97pct <- -1;
    int cycle_99pct <- -1;
    int cycle_100pct <- -1;
    bool milestones_fully_logged <- false;			// write-once guard for the milestone summary row

    /*
     * FINE-GRAINED (1%) DIFFUSION CURVE (v2.16). The 13-checkpoint milestone set is enough to
     * compare scenarios against each other, but not enough to properly characterise the SHAPE of
     * the diffusion curve itself -- checked directly by comparing against the raw (uncorrected)
     * trajectory log, which showed ~47.6% mean adoption already reached by cycle 5 alone, well
     * within the gap between the 35% and 50% checkpoints. This tracks every 1% threshold (101
     * points including 0%) instead of 13, using a list rather than 101 separate named variables
     * for conciseness. Intended for a SINGLE targeted high-resolution baseline run, not the full
     * scenario suite -- the other scenarios' comparisons don't depend on curve shape and don't
     * need this resolution.
     */
    list<int> pct_thresholds <- [];		// populated in global init below via a plain loop, see reflex-free init block
    list<int> fine_cycle_at_pct <- [];		// populated in global init below, same reason
    bool fine_curve_fully_logged <- false;

    /*
     * SME vs LARGE-ORGANISATION DIFFUSION MILESTONES (v2.13). SMEs are documented as less
     * prepared for security threats than larger organisations (Schindler and Ruhland 2022).
     * These milestones test whether business_small+startup_it ("SME group") lag behind
     * enterprise+enterprise_medium ("large group"), and whether the intervention scenarios
     * (government, top-down, bottom-up) close or widen that gap. Same 13-checkpoint design as the population-wide milestones above, computed separately for
     * each group's own sub-population size (not the full organisations count).
     */
    int nb_sme <- nb_business_small + nb_startup_it;					// business_small + startup_it
    int nb_large <- nb_enterprise + nb_enterprise_medium;				// enterprise + enterprise_medium

    int sme_threshold_5pct <- int(ceil(nb_sme * 0.05));
    int sme_threshold_10pct <- int(ceil(nb_sme * 0.10));
    int sme_threshold_20pct <- int(ceil(nb_sme * 0.20));
    int sme_threshold_35pct <- int(ceil(nb_sme * 0.35));
    int sme_threshold_50pct <- int(ceil(nb_sme * 0.50));
    int sme_threshold_60pct <- int(ceil(nb_sme * 0.60));
    int sme_threshold_75pct <- int(ceil(nb_sme * 0.75));
    int sme_threshold_80pct <- int(ceil(nb_sme * 0.80));
    int sme_threshold_90pct <- int(ceil(nb_sme * 0.90));
    int sme_threshold_95pct <- int(ceil(nb_sme * 0.95));
    int sme_threshold_97pct <- int(ceil(nb_sme * 0.97));
    int sme_threshold_99pct <- int(ceil(nb_sme * 0.99));

    int large_threshold_5pct <- int(ceil(nb_large * 0.05));
    int large_threshold_10pct <- int(ceil(nb_large * 0.10));
    int large_threshold_20pct <- int(ceil(nb_large * 0.20));
    int large_threshold_35pct <- int(ceil(nb_large * 0.35));
    int large_threshold_50pct <- int(ceil(nb_large * 0.50));
    int large_threshold_60pct <- int(ceil(nb_large * 0.60));
    int large_threshold_75pct <- int(ceil(nb_large * 0.75));
    int large_threshold_80pct <- int(ceil(nb_large * 0.80));
    int large_threshold_90pct <- int(ceil(nb_large * 0.90));
    int large_threshold_95pct <- int(ceil(nb_large * 0.95));
    int large_threshold_97pct <- int(ceil(nb_large * 0.97));
    int large_threshold_99pct <- int(ceil(nb_large * 0.99));

    int sme_finished_adopting <- 0;
    int large_finished_adopting <- 0;

    int sme_cycle_5pct <- -1;
    int sme_cycle_10pct <- -1;
    int sme_cycle_20pct <- -1;
    int sme_cycle_35pct <- -1;
    int sme_cycle_50pct <- -1;
    int sme_cycle_60pct <- -1;
    int sme_cycle_75pct <- -1;
    int sme_cycle_80pct <- -1;
    int sme_cycle_90pct <- -1;
    int sme_cycle_95pct <- -1;
    int sme_cycle_97pct <- -1;
    int sme_cycle_99pct <- -1;
    int sme_cycle_100pct <- -1;

    int large_cycle_5pct <- -1;
    int large_cycle_10pct <- -1;
    int large_cycle_20pct <- -1;
    int large_cycle_35pct <- -1;
    int large_cycle_50pct <- -1;
    int large_cycle_60pct <- -1;
    int large_cycle_75pct <- -1;
    int large_cycle_80pct <- -1;
    int large_cycle_90pct <- -1;
    int large_cycle_95pct <- -1;
    int large_cycle_97pct <- -1;
    int large_cycle_99pct <- -1;
    int large_cycle_100pct <- -1;

    bool group_milestones_fully_logged <- false;		// write-once guard, mirrors milestones_fully_logged above
    
    list save_adopt <- ["\n", "Agents", organisations, "\n", "Monat", "agents adopted PQS","\n"]; 											// List for exporting a .csf when each agent changed their status to PQS
    int plot_data <- 0;	
    int last_adopt <-0;
    int save_once <-1;																//
    float sum_outdegree <- -0.000000000000001;											// social link sum of all outdegree values
    float degree_of_market_pressure <- 0.00001;
    int finished_adopting <- 0;
    
    list agents_location;																// on what point the agent is assigned
  
  

    list<int> adopting_status;
    list<int> adopting_status_enterprise;
    list<int> adopting_status_enterprise_medium;    
    list<int> adopting_status_business_small;
    list<int> adopting_status_startup_it;
            																			// list of agents that switched to PQS
    int adopt_status <- sum(adopting_status);
    int adopt_status_enterprise <- sum(adopting_status_enterprise);											// number of agents that switched to PQS
    int adopt_status_enterprise_medium <- sum(adopting_status_enterprise_medium);	
    int adopt_status_business_small <- sum(adopting_status_business_small);	
    int adopt_status_startup_it <- sum(adopting_status_startup_it);	
           
    market the_market;																	// needed to calculate the market pressure
    geometry shape <- envelope(shapefile_dot);

	// --- performance switches for batch / headless runs ---
	bool enable_link_visualization <- true;		// turn off in batch experiments: link drawing is purely cosmetic
	int csv_flush_every <- 0;						// 0 = only write CSV once, at end_simulation. >0 = also flush every N cycles.

	// --- batch CSV logging (safe pattern for concurrent replicates) ---
	bool is_batch <- false;						// each batch experiment sets this true in its init
	int trajectory_log_interval <- 5;				// log every N cycles (not every cycle -- keeps row counts sane
													// across hundreds of replicates while still resolving the
													// diffusion curve's shape, not just its endpoint)
	string trajectory_output_path <- model_version + "_scenario_output.csv";	// each experiment overrides this in its init

	// --- scenario switches & parameters (concept, "Future simulation scenarios") ---
	// Government levers act through the model's own equation terms (concept Eq.34/35/38):
	float gov_subsidy_amount <- 0.0;				// [0,1] applied to every org's fin_matching (Eq.35) -- direct injected funds
	float gov_desire_weight_govfin <- 1.0;			// applied to every org's d_govfin (Eq.38) -- how strongly funding incentive drives desire_adopt
	float gov_desire_weight_govleg <- 1.0;			// applied to every org's d_govleg (Eq.38) -- how strongly legal mandate drives desire_adopt

	/*
	 * SINGLE GOVERNMENT ACTOR (v2.23). gov_fin and gov_leg are a weighted blend of one shared
	 * government signal and each organisation's own independent variation:
	 *     gov_x = tie * multiplier_x * signal_x + (1 - tie) * rnd(-1, 1)
	 * with signal_fin = gov_subsidy_amount and signal_leg = legal_stringency. The tie strength and
	 * both multipliers are fixed per organisation type (declared in each species):
	 *   - tie strength follows the Triple Helix view of government-industry-research proximity
	 *     (Etzkowitz and Leydesdorff 2000); enterprise_medium represents research-intensive
	 *     organisations and has the strongest tie;
	 *   - the legal multiplier follows the NIS2 essential / important / below-threshold tiering;
	 *   - the financial multiplier reflects evidence that subsidies are more effective for small
	 *     firms and partly crowd out private investment in large firms.
	 * The government is modelled as this fixed-effects blend rather than as a separate agent with
	 * explicit network links; a link-based government agent is left for future work.
	 */
	float legal_stringency <- 0.0;					// magnitude of legal/regulatory pressure, counterpart to gov_subsidy_amount.
													// Default 0.0: without active intervention gov_leg stays symmetric noise
													// around 0, identical to the behaviour before v2.23.

	// Scenario 2 override globals -- GAMA batch `parameter var:` must bind to a GLOBAL, not a species
	// attribute, so these mirror org.d_prob_cost / org.d_in_know and get pushed onto every agent at init.
	float override_d_prob_cost <- 1.0;
	float override_d_in_know <- 1.0;

	/*
	 * DESIRE_ADOPT CONSTANT C (Eq. 5, v2.18 / v2.25). desire_adopt = sigmoid(weighted sum - C).
	 * The concept specifies C = 1.5. A Monte Carlo estimate of the weighted sum at cycle 0 gives
	 * mean approx. 1.7 and sd approx. 1.27, so with C = 1.5 about 56% of agents start above the
	 * 50% adoption probability, which produces a large adoption surge in the first cycles. The
	 * default is therefore C = 3.0 (about 16% of agents start above 50%). C = 1.5 is still used by
	 * Scenario 1C, which compares 1.5 / 1.75 / 2.0 / 3.0 / 3.5 / 4.0 directly.
	 */
	float desire_adopt_constant <- 3.0;

	/*
	 * STARTING INERTIA (v2.20). With the default of 0.0, check_inertia's `inertia <= 0` condition
	 * is met almost immediately for the whole population, so nearly every agent makes its first
	 * decision in the same cycle. This synchronised first decision causes the initial adoption
	 * surge seen for every value of desire_adopt_constant (the constant only changes how many of
	 * those first decisions are adoptions). A higher starting inertia delays the first decision.
	 * Result (Scenarios 1D/1E): a single shared value delays the surge but does not spread it out;
	 * per-agent random values reduce the surge but show non-monotonic completion times.
	 */
	float starting_inertia <- 0.0;					// default matches the original/current behaviour
	bool randomize_starting_inertia <- false;		// when true, each agent draws its own starting inertia
													// from [0, starting_inertia] instead of all sharing
													// the same fixed value -- see org's init{} block.

	/*
	 * TYPE-DIFFERENTIATED STARTING INERTIA (v2.22). The literature supports opposite expectations
	 * for how inertia scales with organisation size: larger organisations face more procedural
	 * inertia (approval chains, more stakeholders; Vagnani and Volpe 2017), while smaller
	 * organisations need more time to build the financial resources to start, despite being more
	 * agile once resourced (Escoz Barragan and Becker 2025). starting_inertia_large and
	 * starting_inertia_sme let the large group (enterprise + enterprise_medium) and the SME group
	 * (business_small + startup_it) draw from different ranges (Scenario 1F). differentiate_inertia_by_type switches org's init{} logic from the
	 * single shared starting_inertia (Scenario 1E) to these two type-specific bounds instead.
	 */
	float starting_inertia_large <- 0.0;			// upper bound for enterprise + enterprise_medium
	float starting_inertia_sme <- 0.0;				// upper bound for business_small + startup_it
	bool differentiate_inertia_by_type <- false;	// when true (and randomize_starting_inertia is
													// also true), use the two type-specific bounds
													// above instead of the single shared starting_inertia

	// Scenario 6 (sensitivity screen) override globals -- same pattern, covering the remaining
	// desire_adopt (Eq.38) weights not already exposed above (govfin/govleg reuse the Scenario 3
	// globals since they mean the same thing).
	float override_d_precus <- 1.0;
	float override_d_premar <- 1.0;
	float override_d_com <- 1.0;
	float override_d_man <- 1.0;
	float override_d_emp <- 1.0;

	bool scenario_topdown <- false;				// Scenario 4
	int nb_topdown_hubs <- 2;

	bool scenario_bottomup <- false;				// Scenario 5
	float bottomup_eager_share <- 0.3;

	/*
	 * single place-finding action, replacing 5x duplicated inline blocks.
	 * still O(n) worst case against agents_location, but at least it exists once
	 * and is easy to swap for an unused-index pool if agent counts grow much further.
	 */
	point assign_free_location {
		point position <- any_location_in(one_of(dot));
		loop while: agents_location contains position {
			position <- any_location_in(one_of(dot));
		}
		agents_location <- agents_location + position;
		return position;
	}


	/*
7	 * all intentions available to the agent
	 */
	 
    predicate overcome_inertia <- new_predicate("overcome inertia");
    predicate adopt <- new_predicate("adopting new PQS-Encryption");
    predicate idle <- new_predicate("will not be adopting new PQS-Encryption");
    predicate check_improvements <- new_predicate("improving probability of adoption");
    predicate improve_know <- new_predicate("improving internal knowledge");
    predicate improve_man <- new_predicate("improving management");
    predicate improve_emp <- new_predicate("improving employes");
    
    init {
    	/*
    	 * a seed can be assigned to reproduce the exact same rnd value assignment
    	 * useful for testing and verifying of functionality
    	 * (some testing seeds include: 123756410.0 || 1997451170.0 )	
    	 */
   		// seed<- 1997451170.0;		
   		
   		/*
   		 * Built with a plain loop/add: a one-line collect/range declaration throws
   		 * "Boolean cannot be cast to IExpression" in GAMA 2025.6.4 (v2.17).
   		 */
   		loop i from: 0 to: 100 {
   			add int(ceil(organisations * i / 100.0)) to: pct_thresholds;
   			add -1 to: fine_cycle_at_pct;
   		}
   		
		create dot from: shapefile_dot;
        create market {
            the_market <- self;    
        }
        
		/*
		 * creating all agents
		 * number of agents depends on the number declared. 
		 * if no specific type of agent is declared or the total of specific agents < the maximum declared amount, random default agents will be created 
		 * agents will be placed on any location from the shapefile that is still free 
		 * 
		 */
		 
        create enterprise number: nb_enterprise {
        	location <- world.assign_free_location();
    	}
        create enterprise_medium number: nb_enterprise_medium {
        	location <- world.assign_free_location();
    	}
        create business_small number: nb_business_small {
        	location <- world.assign_free_location();
    	}
        create startup_it number: nb_startup_it {
        	location <- world.assign_free_location();
    	}
    	// NOTE: base `org` species is intentionally never instantiated directly -- every agent
    	// created above always has a concrete type. `org` exists only as an abstract parent
    	// carrying the shared BDI plans/rules that enterprise/medium/small/startup all inherit.

    	/*
    	 * Government influence (Scenarios 3 and 7): gov_subsidy_amount injects funds via fin_matching
    	 * (concept Eq.35), while gov_desire_weight_govfin / gov_desire_weight_govleg set how strongly
    	 * financial incentive and legal mandate drive desire_adopt (concept Eq.38). The government's
    	 * signal itself enters gov_fin / gov_leg at agent creation (see SINGLE GOVERNMENT ACTOR).
    	 */
    	if gov_subsidy_amount > 0 or gov_desire_weight_govfin != 1.0 or gov_desire_weight_govleg != 1.0 {
    		ask enterprise+enterprise_medium+business_small+startup_it parallel: false {
    			fin_matching <- gov_subsidy_amount;
    			d_govfin <- gov_desire_weight_govfin;
    			d_govleg <- gov_desire_weight_govleg;
    		}
    	}

    	/* Scenario 2 (improved runs): push global override weights onto every agent, same pattern. */
    	if override_d_prob_cost != 1.0 or override_d_in_know != 1.0 {
    		ask enterprise+enterprise_medium+business_small+startup_it parallel: false {
    			d_prob_cost <- override_d_prob_cost;
    			d_in_know <- override_d_in_know;
    		}
    	}

    	/* Scenario 6 (sensitivity screen): remaining desire_adopt (Eq.38) weights, same pattern. */
    	if override_d_precus != 1.0 or override_d_premar != 1.0 or override_d_com != 1.0
    		or override_d_man != 1.0 or override_d_emp != 1.0 {
    		ask enterprise+enterprise_medium+business_small+startup_it parallel: false {
    			d_precus <- override_d_precus;
    			d_premar <- override_d_premar;
    			d_com <- override_d_com;
    			d_man <- override_d_man;
    			d_emp <- override_d_emp;
    		}
    	}

    	/*
    	 * Scenario 4 (top-down influence): a handful of enterprise agents get pushed toward
    	 * near-maximal internal factors so they clear inertia fastest and, once adopted,
    	 * contribute the most to pre_mar/market pressure for everyone else.
    	 */
    	if scenario_topdown {
    		ask nb_topdown_hubs among enterprise {
    			emp <- 0.9; man <- 0.9; in_know <- 0.9; in_res <- 0.9; ra <- 0.9;
    		}
    	}

    	/*
    	 * Scenario 5 (bottom-up influence): a configurable share of small/startup agents
    	 * are set up as eager early adopters (high internal factors) to represent
    	 * "multiple adoption-interested companies" generating pressure from below.
    	 */
    	if scenario_bottomup {
    		ask (bottomup_eager_share * length(business_small)) among business_small {
    			emp <- 0.85; man <- 0.85; in_know <- 0.85; in_res <- 0.85;
    		}
    		ask (bottomup_eager_share * length(startup_it)) among startup_it {
    			emp <- 0.85; man <- 0.85; in_know <- 0.85; in_res <- 0.85;
    		}
    	}
    }
    /*
     * creating the social link similar to a graph
     * each agent is considered a vertex with a outdegree that can be specified 
     * outdegree depends on the type of agent:
     * 		enterprise = maximum outdegree = number of total agents decflared in (organisations)
     * 		enterprise medium = maximum outdegree = half the number of total agents
     * 		small business = maximum outdegree = 1/4th the number of total agents
     * 		startup = maximum outdegree = 1/3rd the number of total agents
     * 
     * a display will be created with the links between agents and based on their specific color
     * 		enterprise = black
     * 		enterprise medium = blue
     * 		small business = green
     * 		startup = red  
     */
    
    /*
     * This reflex does two separate jobs: (1) drawing link lines (cosmetic, gated by
     * enable_link_visualization) and (2) updating outdegree and degree_of_market_pressure, on
     * which pre_mar depends. Only (1) is gated, so pre_mar is also computed in batch runs.
     * Already-processed links are tracked per agent (counted_links) instead of rescanning the
     * whole link population every cycle, avoiding an O(n^2) per-cycle cost.
     */
    /*
     * Population aggregates (degree_of_market_pressure, sum_outdegree, finished_adopting) are
     * recomputed each cycle from the simulation's own agents instead of being accumulated
     * incrementally in global variables. Introduced in v2.7 while investigating an apparent
     * batch-size effect that was later identified as a measurement artefact (see v2.12 and the
     * write-once milestone logs); kept because recomputation is simple and robust.
     */
    reflex recompute_population_aggregates {
        list<org> all_orgs <- enterprise+enterprise_medium+business_small+startup_it;
        degree_of_market_pressure <- 0.00001 + sum(all_orgs collect length(each.counted_links));
        sum_outdegree <- -0.000000000000001 + sum((all_orgs where (each.status = 8)) collect each.outdegree);
        finished_adopting <- length(all_orgs where (each.status = 8));
        /*
         * Species unions are assigned to typed list<org> variables before applying `where`;
         * filtering an inline union directly throws "MetaPopulation cannot be cast to ISpecies".
         */
        list<org> sme_orgs <- business_small+startup_it;
        list<org> large_orgs <- enterprise+enterprise_medium;
        sme_finished_adopting <- length(sme_orgs where (each.status = 8));
        large_finished_adopting <- length(large_orgs where (each.status = 8));
    }

    /*
     * SME vs LARGE-ORGANISATION MILESTONE TRACKING (v2.13), same pattern as the population-wide
     * track_diffusion_milestones reflex -- runs every cycle, captures each threshold's exact
     * crossing cycle for both groups independently.
     */
    reflex track_group_diffusion_milestones when: not group_milestones_fully_logged {
        if (sme_cycle_5pct = -1) and (sme_finished_adopting >= sme_threshold_5pct) { sme_cycle_5pct <- cycle; }
        if (sme_cycle_10pct = -1) and (sme_finished_adopting >= sme_threshold_10pct) { sme_cycle_10pct <- cycle; }
        if (sme_cycle_20pct = -1) and (sme_finished_adopting >= sme_threshold_20pct) { sme_cycle_20pct <- cycle; }
        if (sme_cycle_35pct = -1) and (sme_finished_adopting >= sme_threshold_35pct) { sme_cycle_35pct <- cycle; }
        if (sme_cycle_50pct = -1) and (sme_finished_adopting >= sme_threshold_50pct) { sme_cycle_50pct <- cycle; }
        if (sme_cycle_60pct = -1) and (sme_finished_adopting >= sme_threshold_60pct) { sme_cycle_60pct <- cycle; }
        if (sme_cycle_75pct = -1) and (sme_finished_adopting >= sme_threshold_75pct) { sme_cycle_75pct <- cycle; }
        if (sme_cycle_80pct = -1) and (sme_finished_adopting >= sme_threshold_80pct) { sme_cycle_80pct <- cycle; }
        if (sme_cycle_90pct = -1) and (sme_finished_adopting >= sme_threshold_90pct) { sme_cycle_90pct <- cycle; }
        if (sme_cycle_95pct = -1) and (sme_finished_adopting >= sme_threshold_95pct) { sme_cycle_95pct <- cycle; }
        if (sme_cycle_97pct = -1) and (sme_finished_adopting >= sme_threshold_97pct) { sme_cycle_97pct <- cycle; }
        if (sme_cycle_99pct = -1) and (sme_finished_adopting >= sme_threshold_99pct) { sme_cycle_99pct <- cycle; }
        if (sme_cycle_100pct = -1) and (sme_finished_adopting >= nb_sme) { sme_cycle_100pct <- cycle; }

        if (large_cycle_5pct = -1) and (large_finished_adopting >= large_threshold_5pct) { large_cycle_5pct <- cycle; }
        if (large_cycle_10pct = -1) and (large_finished_adopting >= large_threshold_10pct) { large_cycle_10pct <- cycle; }
        if (large_cycle_20pct = -1) and (large_finished_adopting >= large_threshold_20pct) { large_cycle_20pct <- cycle; }
        if (large_cycle_35pct = -1) and (large_finished_adopting >= large_threshold_35pct) { large_cycle_35pct <- cycle; }
        if (large_cycle_50pct = -1) and (large_finished_adopting >= large_threshold_50pct) { large_cycle_50pct <- cycle; }
        if (large_cycle_60pct = -1) and (large_finished_adopting >= large_threshold_60pct) { large_cycle_60pct <- cycle; }
        if (large_cycle_75pct = -1) and (large_finished_adopting >= large_threshold_75pct) { large_cycle_75pct <- cycle; }
        if (large_cycle_80pct = -1) and (large_finished_adopting >= large_threshold_80pct) { large_cycle_80pct <- cycle; }
        if (large_cycle_90pct = -1) and (large_finished_adopting >= large_threshold_90pct) { large_cycle_90pct <- cycle; }
        if (large_cycle_95pct = -1) and (large_finished_adopting >= large_threshold_95pct) { large_cycle_95pct <- cycle; }
        if (large_cycle_97pct = -1) and (large_finished_adopting >= large_threshold_97pct) { large_cycle_97pct <- cycle; }
        if (large_cycle_99pct = -1) and (large_finished_adopting >= large_threshold_99pct) { large_cycle_99pct <- cycle; }
        if (large_cycle_100pct = -1) and (large_finished_adopting >= nb_large) { large_cycle_100pct <- cycle; }
    }

    /*
     * Writes ONE summary row per simulation, once, when BOTH groups have finished (or the safety
     * cap is hit) -- same write-once/derived-path pattern as log_diffusion_milestones. Path:
     * trajectory_output_path with .csv swapped for _group_milestones.csv.
     */
    reflex log_group_diffusion_milestones when: (not group_milestones_fully_logged)
        and (((sme_finished_adopting >= nb_sme) and (large_finished_adopting >= nb_large)) or (cycle = max_cycle_safety_cap)) {
        group_milestones_fully_logged <- true;
        int replicate_index <- int(self);
        string group_milestone_path <- copy_between(trajectory_output_path, 0, length(trajectory_output_path) - 4)
            + "_group_milestones.csv";
        save [model_version, seed, replicate_index, agent_count_scale,
              override_d_prob_cost, override_d_in_know, override_d_precus, override_d_premar,
              override_d_com, override_d_man, override_d_emp,
              gov_subsidy_amount, gov_desire_weight_govfin, gov_desire_weight_govleg,
              scenario_topdown, scenario_bottomup, nb_topdown_hubs, bottomup_eager_share,
              nb_sme, sme_cycle_5pct, sme_cycle_10pct, sme_cycle_20pct, sme_cycle_35pct,
              sme_cycle_50pct, sme_cycle_60pct, sme_cycle_75pct, sme_cycle_80pct, sme_cycle_90pct,
              sme_cycle_95pct, sme_cycle_97pct, sme_cycle_99pct, sme_cycle_100pct, sme_finished_adopting,
              nb_large, large_cycle_5pct, large_cycle_10pct, large_cycle_20pct, large_cycle_35pct,
              large_cycle_50pct, large_cycle_60pct, large_cycle_75pct, large_cycle_80pct, large_cycle_90pct,
              large_cycle_95pct, large_cycle_97pct, large_cycle_99pct, large_cycle_100pct, large_finished_adopting]
            to: group_milestone_path
            format: "csv"
            rewrite: false
            header: true;
    }

    reflex compute_social_pressure {
        loop tempOrg over: enterprise+enterprise_medium+business_small+startup_it{
			int outdegree_bound <- organisations/3;
			rgb link_color <- #red;
			if tempOrg.type_org = 1 {
				outdegree_bound <- organisations;
				link_color <- #black;
			} else if tempOrg.type_org = 2 {
				outdegree_bound <- organisations/2;
				link_color <- #blue;
			} else if tempOrg.type_org = 3 {
				outdegree_bound <- organisations/4;
				link_color <- #green;
			}
            loop tempDestination over: tempOrg.social_link_base{
                if (tempDestination != nil) and not (tempOrg.counted_links contains tempDestination.agent) {
                    tempOrg.counted_links <- tempOrg.counted_links + tempDestination.agent;
                    int max_outdegree_of_vertex <- rnd(outdegree_bound);
                    int some_degree <- rnd(outdegree_bound);
                    bool counted <- (tempDestination.liking > 0) and (some_degree < max_outdegree_of_vertex);
                    if counted {
                        tempOrg.outdegree <- tempOrg.outdegree + 1;
                        // degree_of_market_pressure is recomputed in recompute_population_aggregates.
                    }
                    if enable_link_visualization {
                        rgb drawn_color <- rgb(rgb(0,0,0),0);
                        if counted {
                            drawn_color <- link_color;
                        }
                        create socialLinkRepresentation number: 1 {
                            origin <- tempOrg;
                            destination <- tempDestination.agent;
                            my_color <- drawn_color;
                        }
                    }
                }
            }
        }
    }
	/*
	 * Option to export a csv file 
	 * currently will save a list of 
	 * how many agents have switched to PQS and the cycle when a change occured
	 * this can be adjusted and added to if needed
	 */

	/*
	 * Legacy result list (save_adopt). Bookkeeping happens in memory every cycle; writing to disk is
	 * deferred to end_simulation (writing every cycle in every replicate is an I/O bottleneck), with
	 * an optional periodic flush (csv_flush_every) for intermediate checkpoints in very long runs.
	 */
	reflex save_result when: true {
			add cycle to:save_adopt;
			add finished_adopting to: save_adopt;
			if plot_data != finished_adopting {
				plot_data <- finished_adopting;
				last_adopt <- cycle;
			}
			if finished_adopting = organisations and save_once {
				add cycle to: save_adopt;
				add finished_adopting to: save_adopt;
				save_once <- 0;
			}
			add "\n" to: save_adopt;

			if (csv_flush_every > 0) and (cycle mod csv_flush_every = 0) {
				save (save_adopt) to: "results"+name+".csv" format:"csv";
			}
	}

	/*
	 * Shared trajectory log. Defined in `global`, so it runs for every simulation, including every
	 * batch replicate, with one column schema for all scenarios (unused columns keep defaults).
	 *  - Header: every simulation writes its own header at cycle 0. Combined batch files therefore
	 *    contain one header row per replicate; filter them when reading (e.g. df[df.seed != "seed"]).
	 *    Approaches that write a single header via int(self) = 0 did not work reliably in batch mode.
	 *  - replicate_index (int(self)) is logged so the position of a replicate within its batch is
	 *    known exactly.
	 *  - current_pre_mar, sum_outdegree, degree_of_market_pressure and the per-group adoption
	 *    counts (v2.24) show which group's adopters drive the shared market-pressure signal.
	 *  - Completion times must be taken from the milestone logs, not from the last row of this log
	 *    (replicates can continue past completion in batch mode; see header).
	 */
	reflex log_trajectory when: cycle mod trajectory_log_interval = 0 {
		int replicate_index <- int(self);
		float current_pre_mar <- sum_outdegree/degree_of_market_pressure;	// pre_mar itself is a per-agent attribute
																			// (though numerically identical for everyone,
																			// since it's computed from these same two
																			// globals) -- recomputed here directly since
																			// a global reflex can't reference a species attribute.
		save [model_version, seed, replicate_index, cycle, agent_count_scale,
			  override_d_prob_cost, override_d_in_know, override_d_precus, override_d_premar,
			  override_d_com, override_d_man, override_d_emp,
			  gov_subsidy_amount, gov_desire_weight_govfin, gov_desire_weight_govleg,
			  scenario_topdown, scenario_bottomup, nb_topdown_hubs, bottomup_eager_share,
			  finished_adopting, organisations,
			  current_pre_mar, sum_outdegree, degree_of_market_pressure,
			  sme_finished_adopting, large_finished_adopting, nb_sme, nb_large]
			to: trajectory_output_path
			format: "csv"
			rewrite: false
			header: (cycle = 0);
	}

	/*
	 * S-CURVE DIFFUSION MILESTONES (v2.12), part 1: runs EVERY cycle (not gated by
	 * trajectory_log_interval like log_trajectory above) so each milestone's crossing cycle is
	 * captured exactly, not rounded to the nearest 5-cycle log point.
	 */
	reflex track_diffusion_milestones when: not milestones_fully_logged {
		if (cycle_5pct = -1) and (finished_adopting >= threshold_5pct) { cycle_5pct <- cycle; }
		if (cycle_10pct = -1) and (finished_adopting >= threshold_10pct) { cycle_10pct <- cycle; }
		if (cycle_20pct = -1) and (finished_adopting >= threshold_20pct) { cycle_20pct <- cycle; }
		if (cycle_35pct = -1) and (finished_adopting >= threshold_35pct) { cycle_35pct <- cycle; }
		if (cycle_50pct = -1) and (finished_adopting >= threshold_50pct) { cycle_50pct <- cycle; }
		if (cycle_60pct = -1) and (finished_adopting >= threshold_60pct) { cycle_60pct <- cycle; }
		if (cycle_75pct = -1) and (finished_adopting >= threshold_75pct) { cycle_75pct <- cycle; }
		if (cycle_80pct = -1) and (finished_adopting >= threshold_80pct) { cycle_80pct <- cycle; }
		if (cycle_90pct = -1) and (finished_adopting >= threshold_90pct) { cycle_90pct <- cycle; }
		if (cycle_95pct = -1) and (finished_adopting >= threshold_95pct) { cycle_95pct <- cycle; }
		if (cycle_97pct = -1) and (finished_adopting >= threshold_97pct) { cycle_97pct <- cycle; }
		if (cycle_99pct = -1) and (finished_adopting >= threshold_99pct) { cycle_99pct <- cycle; }
		if (cycle_100pct = -1) and (finished_adopting >= organisations) { cycle_100pct <- cycle; }
	}

	/*
	 * S-CURVE DIFFUSION MILESTONES (v2.12), part 2: writes ONE summary row per simulation, once,
	 * when the simulation actually ends (full adoption or the safety cap) -- not a per-cycle log
	 * like log_trajectory, since these values only change once each and a full row per cycle
	 * would be redundant. Output path is derived automatically from trajectory_output_path
	 * (swap the .csv suffix for _milestones.csv) rather than requiring every one of the 58
	 * experiments to separately declare a second output path.
	 * header: true unconditionally, not header: (cycle=0) -- this reflex doesn't fire at cycle=0.
	 * Relies on the same GAMA behaviour already confirmed for log_trajectory: even though every
	 * simulation requests a header, GAMA only actually writes one when the target file doesn't
	 * already have content, so this reliably produces exactly one header despite the naive-looking
	 * unconditional request.
	 */
	reflex log_diffusion_milestones when: (not milestones_fully_logged)
		and ((finished_adopting >= organisations) or (cycle = max_cycle_safety_cap)) {
		milestones_fully_logged <- true;
		int replicate_index <- int(self);
		string milestone_path <- copy_between(trajectory_output_path, 0, length(trajectory_output_path) - 4)
			+ "_milestones.csv";
		save [model_version, seed, replicate_index, agent_count_scale,
			  override_d_prob_cost, override_d_in_know, override_d_precus, override_d_premar,
			  override_d_com, override_d_man, override_d_emp,
			  gov_subsidy_amount, gov_desire_weight_govfin, gov_desire_weight_govleg,
			  scenario_topdown, scenario_bottomup, nb_topdown_hubs, bottomup_eager_share,
			  cycle_5pct, cycle_10pct, cycle_20pct, cycle_35pct, cycle_50pct, cycle_60pct,
			  cycle_75pct, cycle_80pct, cycle_90pct, cycle_95pct, cycle_97pct, cycle_99pct,
			  cycle_100pct, finished_adopting, organisations]
			to: milestone_path
			format: "csv"
			rewrite: false
			header: true;
	}

	/*
	 * FINE-GRAINED (1%) DIFFUSION CURVE (v2.16), part 1: runs every cycle, records the exact
	 * cycle each of the 101 thresholds (0% through 100%) is first crossed. Only meaningfully
	 * different from track_diffusion_milestones above in resolution -- same write-once-per-
	 * threshold logic, applied to every integer percentage instead of 13 checkpoints.
	 */
	reflex track_fine_curve when: not fine_curve_fully_logged {
		loop i from: 0 to: 100 {
			if (fine_cycle_at_pct[i] = -1) and (finished_adopting >= pct_thresholds[i]) {
				put cycle at: i in: fine_cycle_at_pct;
			}
		}
	}

	/*
	 * FINE-GRAINED (1%) DIFFUSION CURVE (v2.16), part 2: writes ONE row per simulation with all
	 * 101 crossing-cycles as a single list-valued cell (GAMA serialises a list to one CSV field,
	 * e.g. "[0,0,2,2,...]") rather than 101 separate columns, for conciseness -- parse with a
	 * standard list/array literal reader (e.g. Python's ast.literal_eval) when analysing.
	 * Same derived-path pattern as the other loggers: trajectory_output_path with .csv swapped
	 * for _finecurve.csv.
	 */
	reflex log_fine_curve when: (not fine_curve_fully_logged)
		and ((finished_adopting >= organisations) or (cycle = max_cycle_safety_cap)) {
		fine_curve_fully_logged <- true;
		int replicate_index <- int(self);
		string fine_curve_path <- copy_between(trajectory_output_path, 0, length(trajectory_output_path) - 4)
			+ "_finecurve.csv";
		save [model_version, seed, replicate_index, agent_count_scale, organisations, fine_cycle_at_pct]
			to: fine_curve_path
			format: "csv"
			rewrite: false
			header: true;
	}
	
  	/*
  	 * Simulations stop through the experiments' `until:` condition (full adoption or
  	 * max_cycle_safety_cap). Full adoption is always reached eventually, because funds grows
  	 * without bound and finally dominates the adoption probability. This reflex only writes the
  	 * legacy result file when the safety cap is hit. It deliberately does not call `do pause;`
  	 * (or any other self-stopping action): in batch mode that pauses the whole experiment
  	 * scheduler and truncates sibling replicates.
  	 */
    	reflex end_simulation when: cycle=max_cycle_safety_cap{	
        save (save_adopt) to: "results"+name+".csv" format:"csv";	// single guaranteed write on completion
        ask enterprise+enterprise_medium+business_small+startup_it parallel: false {
        //	write name;
        //	write "-- stopped inertia at cycle: " + save_cycle_idle;
        //	write "-- adopted at cycle: " + save_cycle_adopt;
    	}
    }
}  
 // drawing dots for the agents
species dot {
    aspect geom {
	draw shape color: #gray;
    }
}

/*
 * market: helper agent that collects adoption status per organisation type, so that the
 * organisations do not each have to query every other agent. It perceives all organisations and
 * records their status in the adopting_status_* lists; the sums (adopt_status_*) are available
 * for display and logging. It is a bookkeeping construct and is not drawn by default.
 */

 
species market control:simple_bdi{
    point target;
   	float view_dist<-10000000000.0;

    // The base `org` species is never instantiated (see global init), so no perceive block tracks
    // type_org = 0. adopting_status / adopt_status remain declared for compatibility and stay 0.
    
    perceive target: enterprise where (each.status = 8 and each.type_org = 1) in: view_dist parallel: false {
		if length(adopting_status_enterprise) >=  nb_enterprise {
			adopting_status_enterprise <- [];
		}
		add 1 to: adopting_status_enterprise;
		adopt_status_enterprise <- sum(adopting_status_enterprise);
    }
    perceive target: enterprise where (each.status != 8 and each.type_org = 1) in: view_dist parallel: false {
		if length(adopting_status_enterprise) >=  nb_enterprise {
			adopting_status_enterprise <- [];
		}
		add 0 to: adopting_status_enterprise;
		adopt_status_enterprise <- sum(adopting_status_enterprise);
    }

    perceive target: enterprise_medium where (each.status = 8 and each.type_org = 2) in: view_dist parallel: false {
		if length (adopting_status_enterprise_medium) >=  nb_enterprise_medium {

			adopting_status_enterprise_medium <- [];
		}
		add 1 to: adopting_status_enterprise_medium;
		adopt_status_enterprise_medium <- sum(adopting_status_enterprise_medium);
    }
    perceive target: enterprise_medium where (each.status != 8 and each.type_org = 2) in: view_dist parallel: false {
		if length (adopting_status_enterprise_medium) >=  nb_enterprise_medium {
			adopting_status_enterprise_medium <- [];
		}
		add 0 to: adopting_status_enterprise_medium;
		adopt_status_enterprise_medium <- sum(adopting_status_enterprise_medium);
    }
  
    perceive target: business_small where (each.status = 8 and each.type_org = 3) in: view_dist parallel: false {
		if length (adopting_status_business_small) >=  nb_business_small {

			adopting_status_business_small <- [];
		}
		add 1 to: adopting_status_business_small;
		adopt_status_business_small <- sum(adopting_status_business_small);
    }
    perceive target: business_small where (each.status != 8 and each.type_org = 3) in: view_dist parallel: false {
		if length (adopting_status_business_small) >=  nb_business_small {
			adopting_status_business_small <- [];
		}
		add 0 to: adopting_status_business_small;
		adopt_status_business_small <- sum(adopting_status_business_small);
    }
    
      perceive target: startup_it where (each.status = 8 and each.type_org = 4) in: view_dist parallel: false {
		if length (adopting_status_startup_it) >=  nb_startup_it {

			adopting_status_startup_it <- [];
		}
		add 1 to: adopting_status_startup_it;
		adopt_status_startup_it <- sum(adopting_status_startup_it);
    }
    perceive target: startup_it where (each.status != 8 and each.type_org = 4) in: view_dist parallel: false {
		if length (adopting_status_startup_it) >=  nb_startup_it {
			adopting_status_startup_it <- [];
		}
		add 0 to: adopting_status_startup_it;
		adopt_status_startup_it <- sum(adopting_status_startup_it);	// FIX: was overwriting adopt_status_business_small (copy-paste bug)
    }    
    
    aspect default {	
    //  draw square(10) color: #black ;
    }
}

/*
 * org is the abstract parent species holding all internal variables, beliefs, rules and plans
 * described in the concept. The four organisation types (enterprise, enterprise_medium,
 * business_small, startup_it) inherit from it and specify their own initial values.
 */


species org control:simple_bdi {
    
    /*
     * probabilistic_choice MUST stay false (v1.9). When true, GAMA's SimpleBdiArchitecture selects
     * obligations by matching mental states against declared norms only; this model declares no
     * norms, so an empty list is passed to Random.opRndChoice every cycle, which throws
     * "Distribution elements should not be all equal to 0" in GAMA 2025.6.4.
     * Weighted-random decisions are instead implemented explicitly with rnd_choice() in
     * check_inertia, idling and improve_odds (v2.0).
     */
    bool probabilistic_choice <- false;
 
 	/*
 	 * Adjustment values for all agents per simulation; most are overridden by the child species.
 	 * For random runs, rnd(-1.0, 1.0) / rnd(0.0, 1.0) can be used.
 	 */
 
 	float inertia <- starting_inertia;								// non-negative; see starting_inertia in globals
 
 	float emp;														// value assigned in parent based on organisation status
	float man; 														// value assigned in parent based on organisation status
 
 	float liking <- rnd(-1.0, 1.0); float dominance <- rnd(-1.0, 1.0); float solidarity <- rnd(0.0, 1.0); float familiarity <- rnd(0.0, 1.0); float trust <- rnd(-1.0, 1.0);
	float com <- (liking+dominance+solidarity+familiarity+trust)/5;	//social link strength
 
 	float gov_fin;													// value assigned in parent based on organisation status
  	float gov_leg; 													// value assigned in parent based on organisation status
   	float pre_cus;													// value assigned in parent based on organisation status
 	float pre_mar <- sum_outdegree/degree_of_market_pressure;  		// recomputed in the plans where it is used
	// EXTENSION of concept Eq.7: the concept defines pre_mar as the plain ratio of adopters to all
	// agents, which does not distinguish a large, well-connected adopter from a small one. Here
	// pre_mar is weighted by the cumulative social-link outdegree of adopted agents, so market
	// pressure scales with how connected the adopters are, not only with their number.
  	float pressure <- pre_mar + pre_cus + gov_leg + gov_fin + com;  // diagnostic aggregate only (all factors incl. com) --
  																	// not used by in_res growth or desire_adopt, which use the
  																	// individually weighted terms of concept Eq.33/34/38.

   	// Initialisers below do not reference their own variable (self-referential initialisers read 0.0).
   	float in_know <- rnd(0.0, 1.0) + emp + man;						// company knowledge + human factors, per Eq.1/comment intent
   	// Concept Eq.34: resource growth uses premar+precus+govleg+govfin (not com).
   	float in_res <- rnd(0.0, 1.0) * (1 + pre_mar + pre_cus + gov_leg + gov_fin);
 	float cost <- rnd(0.0, 1.0) + emp/2 + man/2;						// value assigned in parent based on organisation status
 	float ra;			 											// value assigned in parent based on organisation status 


	float funds <- (in_res + ra * int(cycle/12) + fin_matching); 	// concept Eq.35 (paper Eq. 3), including fin_matching
  	float prob_cost <- 1/(1+exp(-2.75*(funds-cost)));	
 
  	float desire_adopt <- 0.0;					 					// (0-1)
		
	int type_org <- 0;  											// value assigned in parent based on organisation status 0: default (parent agent)  1: Enterprise 2: Medium-Enterprise 3: Small business 4: Startup with IT Background  	  
	
	
	/*
	 * programming specific variables
	 * 
	 */
	float intitial_in_know <- in_know;								
	float initial_cost <- cost;
	int last_status <- 0; 											// buffer variable to save the status of the previous cycle
	int status <- 0;												// 0 -> in Inertia -> 1 in trying to adopt 2-> adopting new encryption

	//float av <- 0.0; 												// will not be needed in a programming point of view, since gama provides an internal variable "cycle" that does exactly what is needed of av						
	
   	float last_pressure <- pressure;								// buffer variable to save the pressure value of the previous cycle
    int outdegree <- 0;												// personal outdegree will be set in social link to it's simulation value
    list<agent> counted_links <- [];									// tracks destinations already accounted for in compute_social_pressure (avoids O(n) rescans of the global link population)
    
    int save_cycle_idle <- 0;										// save parameters
    int save_cycle_adopt <- 0;
    
    //weights for further simulation research
	// Concept Eq.33 (inertia) and Eq.38 (desire_adopt) weight every factor independently. An earlier
	// version collapsed pre_cus+pre_mar+gov_leg+gov_fin+com into one shared weight, which made the
	// government factors impossible to vary separately (required for Scenarios 3 and 7).
	float inert_emp <- 1.0; float inert_man <- 1.0;
	float inert_in_know <- 1.0; float inert_funds <- 1.0;
	float inert_precus <- 1.0; float inert_premar <- 1.0;

	float d_prob_cost <- 1.0; float d_in_know <- 1.0;
	float d_precus <- 1.0; float d_premar <- 1.0; float d_com <- 1.0;
	float d_govleg <- 1.0; float d_govfin <- 1.0;
	float d_man <- 1.0; float d_emp <- 1.0;

	float fin_matching <- 0.0;		// [0,1] Eq.35 -- direct government/matching funds added to `funds`.
									// 0 by default (no matching); Scenario 3 sets this per-agent instead
									// of crudely scaling gov_fin/gov_leg.
    
    /*
     * icon imports, color assignmet 
     * all icons are copyright free and fair use downloaded from: www.flaticon.com
     */ 
     
    float view_dist<-1000000.0;
    rgb my_color<- #green; //rnd_color(255);
    image_file my_icon <- red_lock; 
    image_file green_lock <- image_file("../includes/Icons/padlock_green.png");
    image_file red_lock <- image_file("../includes/Icons/padlock_red.png");
    image_file purple_lock <- image_file("../includes/Icons/padlock_purple.png");
	image_file improvement <- image_file("../includes/Icons/improvement.png");   
	image_file improvement_know <- image_file("../includes/Icons/open-book.png");  	
	image_file improvement_man <- image_file("../includes/Icons/management.png");  	
	image_file improvement_emp <- image_file("../includes/Icons/team.png");  	
	image_file waiting <- image_file("../includes/Icons/time-left.png");  		
	 
    point target;
	
	// enables integrated social link functionality
    bool use_social_architecture <- true;
    
    /*
     * starting each simulation with the desire to get out of the inertia phase
     */
    
    init {
   		/*
   		 * RANDOM STARTING INERTIA (v2.21). A single FIXED starting_inertia shared by every agent
   		 * (Scenario 1D) delayed the population's synchronised first-decision wave but did not
   		 * spread it out -- every curve still showed the same sharp jump, just later. Per-agent
   		 * random variation is the more direct test of genuine staggering: each agent draws its
   		 * own starting inertia independently from [0, starting_inertia], so different agents
   		 * cross their own (different) thresholds at genuinely different cycles, rather than a
   		 * shared threshold being crossed collectively at roughly the same later moment.
   		 * TYPE-DIFFERENTIATED VARIANT (v2.22): when differentiate_inertia_by_type is also true,
   		 * large organisations (type_org 1/2) and SMEs (type_org 3/4) draw from separate ranges
   		 * (starting_inertia_large / starting_inertia_sme) instead of the single shared bound --
   		 * see the declaration comment above for why both directions are tested rather than one
   		 * assumed.
   		 */
   		if randomize_starting_inertia {
   			if differentiate_inertia_by_type {
   				if type_org <= 2 {
   					inertia <- rnd(0.0, starting_inertia_large);
   				} else {
   					inertia <- rnd(0.0, starting_inertia_sme);
   				}
   			} else {
   				inertia <- rnd(0.0, starting_inertia);
   			}
   		}
   	
        /*
         * Explicit strength is required: without it GAMA uses 0.0, and since this is the only desire
         * at cycle 0, the engine's weighted tie-break receives an all-zero distribution and throws
         * "Distribution elements should not be all equal to 0" (v1.6).
         */
        do add_desire(predicate: overcome_inertia, strength: 1.0);
    }
    
    /*
     * social link
     * making a connection to all other agents and coloring them for the graph
     *  
     */ 
    
    perceive target: enterprise+enterprise_medium+business_small+startup_it in: view_dist parallel: false {
        /*
         * Colour distance computed as plain Euclidean arithmetic with explicit float() casts.
         * Building point() objects from rgb channels combined with distance_to intermittently threw
         * "Integer cannot be cast to IExpression" (v2.5).
         */
        float color_distance <- sqrt((float(my_color.red) - float(myself.my_color.red))^2
            + (float(my_color.green) - float(myself.my_color.green))^2
            + (float(my_color.blue) - float(myself.my_color.blue))^2);
        socialize liking: 1 - color_distance / 255;
    }
    
    /*
     * NOTE: these two rules never fire. A rule only triggers while the agent holds the named
     * belief, and no belief "adopt" or "idle" is ever added in this model. They are kept to
     * document the concept's original rule structure; the actual decision (adopt / check for
     * improvements / idle) is made explicitly with rnd_choice in check_inertia and idling.
     */
    rule belief: adopt new_desire: adopt strength: desire_adopt;
    rule belief: idle new_desire: idle strength: 1-desire_adopt;
    
    /*
     * Inertia represents an organisation's ramp-up process (setting aside funding, assigning
     * staff to a new team, etc.). Market pressure is included, since competitors adopting or a
     * growing market can increase the willingness to start. Inertia never grows: while the
     * weighted sum is negative nothing happens, and inertia only decreases once the positive
     * factors outweigh the negative ones. Once inertia reaches 0 the agent makes its first
     * decision (adopt / check for improvements / idle).
     */
    
    plan check_inertia intention: overcome_inertia {

			// update knowledge
			in_know <- intitial_in_know + man + emp;
			if in_know < 0 {
				in_know <- intitial_in_know;
			}
			// update pressure and funds
			pre_mar <- sum_outdegree/degree_of_market_pressure;	
			// `pressure` is a display/diagnostic aggregate only; in_res, desire_adopt and inertia use
			// the independently weighted terms of concept Eq.33/34/38.
			if gov_leg < 0 or gov_fin < 0 {
				pressure <- (pre_mar + pre_cus + gov_leg/2 + gov_fin/2 + com)/5;					
			}else {
				pressure <- (pre_mar + pre_cus + gov_leg + gov_fin + com)/5;					
			}	
			if pressure < 0 {
				pressure <- 0.0;
			}
			// Concept Eq.34: in_res grows with premar+precus+govleg+govfin (com is not part of Eq.34).
			// The previous contribution is removed before the new one is applied, and only when the
			// combined term has changed.
			float market_growth_terms <- pre_mar + pre_cus + gov_leg + gov_fin;
			if market_growth_terms != last_pressure {
				in_res <- in_res-(in_res*last_pressure);
				last_pressure <- market_growth_terms;
				in_res <- in_res+(in_res*market_growth_terms); 					
			}
			// update funds and costs
			funds <- (in_res + ra * int(cycle/12) + fin_matching);	// Eq.35, now includes fin_matching
			// This four-way sign branch computes cost = initial_cost + abs(man)/2 + abs(emp)/2;
			// see the identical block in idling below for the full explanation and verification.
			if man < 0 and emp < 0 {
				cost <- initial_cost + (-1*( man/2 + emp/2)); 
			}else if man < 0 and emp > 0 {
				cost <- initial_cost + (-1*( man/2) + emp/2);  
			}else if man > 0 and emp < 0 {
				cost <- initial_cost + (-1*( emp/2) + man/2); 				
			}else {
				cost <- initial_cost + man/2 + emp/2; 				
			}
					
			// update probabilities

      	 	prob_cost <- 1/(1+exp(-2.75*(funds-cost)));
      	 	// Concept Eq.38 (paper Eq. 5): every factor weighted independently; the constant is
      	 	// desire_adopt_constant (default 3.0, concept value 1.5 -- see globals).
      	 	desire_adopt <- 1/(1+exp(-(d_prob_cost*prob_cost + d_precus*pre_cus + d_premar*pre_mar
      	 		+ d_com*com + d_govleg*gov_leg + d_govfin*gov_fin + d_man*man + d_emp*emp
      	 		+ d_in_know*in_know - desire_adopt_constant)));
      	 	 			
 			// Concept Eq.33 (paper Eq. 1): inertia reduced by independently weighted
 			// emp/man/in_know/funds/precus/premar; applied only while the reduction is positive.
 			float inertia_reduction <- inert_emp*emp + inert_man*man + inert_in_know*in_know
 				+ inert_funds*funds + inert_precus*pre_cus + inert_premar*pre_mar;
 			if inertia_reduction > 0  {  
      			inertia <- inertia - inertia_reduction;      			
      		}
      		if inertia <= 0 {
      			do remove_intention(overcome_inertia, true);
      			do remove_desire(overcome_inertia);
      			/*
      			 * Central decision (v2.0): weighted random choice between adopt (weight desire_adopt),
      			 * check_improvements and idle (weight 1 - desire_adopt each). Implemented explicitly with
      			 * rnd_choice because probabilistic_choice must stay false (see org header). rnd_choice
      			 * normalises the weights itself. Weights are floored at 0.001 because rnd_choice requires
      			 * strictly positive values and desire_adopt can saturate to 0 or 1 in floating point (v2.1).
      			 */
      			float adopt_w <- max(0.001, desire_adopt);
      			float other_w <- max(0.001, 1-desire_adopt);
      			string chosen_intention <- rnd_choice(["adopt"::adopt_w,
      				"check_improvements"::other_w, "idle"::other_w]);
      			if chosen_intention = "adopt" {
      				do add_desire(predicate:adopt, strength: desire_adopt);
      			} else if chosen_intention = "check_improvements" {
      				do add_desire(predicate:check_improvements, strength: 1-desire_adopt);
      			} else {
      				do add_desire(predicate:idle, strength: 1-desire_adopt);
      			}
					my_color <- #blue;
					save_cycle_idle <- cycle +1;
      		}	
    } 
    
    /*
     * Adoption: the agent switches to PQS (status 8) and its display values change. Its outdegree
     * now counts towards sum_outdegree and therefore towards market pressure (recomputed each
     * cycle in recompute_population_aggregates). The adoption cycle is stored as cycle + 1,
     * because cycle starts at 0.
     */
    
    plan adopting intention: adopt {
			my_icon <- green_lock;
       		my_color <- #red;
       		status <- 8;
       		if last_status != status {
       			last_status <- status;
       			// sum_outdegree and finished_adopting are recomputed each cycle in
       			// recompute_population_aggregates.
     			save_cycle_adopt <- cycle +1;
       		}

       } 
    /*
     * Idling. After an improvement (status 4), the agent first waits one cycle to absorb it
     * (status 4 -> 3). It then updates in_know, market pressure, funds, cost and desire_adopt and
     * makes the central decision again (adopt / check for improvements / idle). The resulting
     * sequence after an improvement is: decide, apply, idle, decide.
     */  
       
    plan idling intention: idle {
			if status > 3 {
				status <- status -1;
				my_icon <- waiting;	
			}else {    	
	 			my_icon <- purple_lock;
       			status <- 1;
 				
 				// update knowledge
				in_know <- intitial_in_know + man + emp;
				if in_know < 0 {
					in_know <- intitial_in_know;
				} 				
				// update pressure and funds
				pre_mar <- sum_outdegree/degree_of_market_pressure;
				// `pressure` is a display/diagnostic aggregate only (see check_inertia).
				if gov_leg < 0 or gov_fin < 0 {
					pressure <- (pre_mar + pre_cus + gov_leg/2 + gov_fin/2 + com)/5;					
				}else {
					pressure <- (pre_mar + pre_cus + gov_leg + gov_fin + com)/5;				
				}	
				if pressure < 0 {
					pressure <- 0.0;
				}
				// Concept Eq.34: premar+precus+govleg+govfin (no com), as in check_inertia.
				float market_growth_terms <- pre_mar + pre_cus + gov_leg + gov_fin;
				if market_growth_terms != last_pressure {
					in_res <- in_res-(in_res*last_pressure);
					last_pressure <- market_growth_terms;
					in_res <- in_res+(in_res*market_growth_terms); 					
				}  	
				// update funds and costs
				funds <- (in_res + ra * int(cycle/12) + fin_matching);	// concept Eq.35 (paper Eq. 3)
				/*
				 * The four sign branches below compute cost = initial_cost + abs(man)/2 + abs(emp)/2
				 * (numerically verified for all sign combinations). Both strongly negative
				 * (resistant) and strongly positive (ambitious) management or employee sentiment raise
				 * the cost of the transition; a neutral organisation has the lowest adjustment cost.
				 */
				if man < 0 and emp < 0 {
					cost <- initial_cost + (-1*( man/2 + emp/2)); 
				}else if man < 0 and emp > 0 {
					cost <- initial_cost + (-1*( man/2) + emp/2);  
				}else if man > 0 and emp < 0 {
					cost <- initial_cost + (-1*( emp/2) + man/2); 				
				}else {
					cost <- initial_cost + man/2 + emp/2; 				
				}
				
				// update probabilities -- concept Eq.38 (paper Eq. 5), see check_inertia
      		 	prob_cost <- 1/(1+exp(-2.75*(funds-cost)));
      		 	desire_adopt <- 1/(1+exp(-(d_prob_cost*prob_cost + d_precus*pre_cus + d_premar*pre_mar
      		 		+ d_com*com + d_govleg*gov_leg + d_govfin*gov_fin + d_man*man + d_emp*emp
      		 		+ d_in_know*in_know - desire_adopt_constant)));

				do remove_desire(predicate:idle);
     	 		do remove_desire(predicate:adopt);
     	 		// Central decision: explicit weighted-random pick with positivity floor (see check_inertia).
     	 		float adopt_w <- max(0.001, desire_adopt);
     	 		float other_w <- max(0.001, 1-desire_adopt);
     	 		string chosen_intention <- rnd_choice(["adopt"::adopt_w,
     	 			"check_improvements"::other_w, "idle"::other_w]);
     	 		if chosen_intention = "adopt" {
     	 			do add_desire(predicate:adopt, strength: desire_adopt);
     	 		} else if chosen_intention = "check_improvements" {
     	 			do add_desire(predicate:check_improvements, strength: 1-desire_adopt);
     	 		} else {
     	 			do add_desire(predicate:idle, strength: 1-desire_adopt);
     	 		}
			}
	}

	/*
	 * improve_odds checks whether there is room for improvement, i.e. whether cost is still at or
	 * below 2. If so, the agent chooses one improvement option at random (weights below) and all
	 * other desires are removed; otherwise it idles.
	 */
    plan improve_odds intention: check_improvements {
    	/*
    	 * Three mutually exclusive improvement options, chosen with weights 1 - x (floored at 0.01,
    	 * since in_know/man/emp can grow beyond 1 and rnd_choice requires positive weights):
    	 *   improve_know  buy external knowledge (consulting, training, licensed expertise):
    	 *                 raises in_know and cost by the same amount; man and emp are unchanged.
    	 *   improve_man / improve_emp  invest in management or employees: raises that factor and
    	 *                 in_know, with cost rising by half that amount.
    	 * Building internal capability (man/emp) is therefore more cost-efficient per unit of
    	 * in_know than buying it, reflecting the make-vs-buy distinction in capability acquisition.
    	 */
	 		float probability_in_know <- max(0.01, 1 - in_know);
	 		float probability_man <- max(0.01, 1 - man);
	 		float probability_emp <- max(0.01, 1 - emp);
	 		my_icon <- improvement;
       		status <- 3;    		
       		if cost <= 2 {
       			do remove_desire(predicate:idle);
      			do remove_desire(predicate:adopt);
      			do remove_desire(predicate:check_improvements);
      			// Explicit weighted-random pick (v2.0), see check_inertia.
      			string chosen_improvement <- rnd_choice(["improve_know"::probability_in_know,
      				"improve_man"::probability_man, "improve_emp"::probability_emp]);
      			if chosen_improvement = "improve_know" {
      				do add_desire(predicate:improve_know, strength: probability_in_know);
      			} else if chosen_improvement = "improve_man" {
      				do add_desire(predicate:improve_man, strength: probability_man);
      			} else {
      				do add_desire(predicate:improve_emp, strength: probability_emp);
      			}
       		}else{
       			do remove_desire(predicate:adopt);
      			do remove_desire(predicate:check_improvements);
    		  	do add_desire(predicate:idle, strength: 1.0);
       		}
       }
       
       
     /*
      * improve_know / improve_man / improve_emp
      * based on how much costs and the specific aspect can be increased the agent will adjust those values 
      * for knowledge it's a one to one increase to costs as for man and emp it's a 1 to 2 ratio
      * since there is a corralation between in_know -> man and emp and increase in either of the two will also net an increase in the internal knowledge
      * 	a collective update was considered to check if an improvement occured and model it closer to the beyes network but the increased performance of the current
      * 	implementation outweighs the closer "theoretical" approach
      */         
    /*
     * improving_know: buy external knowledge. Raises in_know and cost by the same amount and
     * leaves man and emp unchanged. No effect once cost >= 1.
     */
    plan improving_know intention: improve_know {
       		float difference_cost <- 1 - cost;
       		float difference_in_know <- 1- in_know;   
	 		my_icon <- improvement_know;
       		status <- 4;			// one absorption cycle in idling before the next decision
       		// Step sizes shrink as in_know grows (diminishing returns); halved in v2.25 so that a
       		// single improvement cannot close most of the gap set by desire_adopt_constant.
       		if cost >= 1{
       			
       		}else if in_know < 0.2 {
       			initial_cost <- initial_cost + 0.2;
       			intitial_in_know <- intitial_in_know + 0.2;
       		}else if  in_know < 0.5 {
       			initial_cost <- initial_cost + 0.1;
       			intitial_in_know <- intitial_in_know + 0.1;     			
       		}else if in_know < 0.75 {
       			initial_cost <- initial_cost + 0.05;
       			intitial_in_know <- intitial_in_know + 0.05;	
       		}else {
      			initial_cost <- initial_cost + 0.025;
       			intitial_in_know <- intitial_in_know + 0.025;
       		}
			do remove_desire(predicate:improve_know);
			do remove_desire(predicate:improve_man);
			do remove_desire(predicate:improve_emp);  
    		do add_desire(predicate:idle, strength: 1.0);
       } 
      plan improving_man intention: improve_man {
       		float difference_cost <- 1 - cost;
       		float difference_man <- 1- man;   
	 		my_icon <- improvement_man;
       		// status 4: exactly one absorption cycle in idling (4 -> 3) before the next decision.
       		status <- 4;
       		// Raises man and in_know by the same step, cost by half of it; step sizes shrink as man
       		// grows (diminishing returns). Halved in v2.25 so that a single improvement cannot close
       		// most of the gap set by desire_adopt_constant. Negative man improves at a small cost saving.
       		if man < 0 {
       			initial_cost <- initial_cost - 0.025;
       			man <- man + 0.05;
       		}else if man < 0.2 {
       			initial_cost <- initial_cost + 0.1;
       			man <- man + 0.2;
       			intitial_in_know <- intitial_in_know + 0.2;
       		}else if man < 0.5 {
       			initial_cost <- initial_cost + 0.075;
       			man <- man + 0.15; 
       			intitial_in_know <- intitial_in_know + 0.15;    			
       		}else if man < 0.75 {
       			initial_cost <- initial_cost + 0.05;
       			man <- man + 0.1;
       			intitial_in_know <- intitial_in_know + 0.1;	
       		}else {
       			initial_cost <- initial_cost + 0.025;
       			man <- man + 0.05;
       			intitial_in_know <- intitial_in_know + 0.05;
       		}
			do remove_desire(predicate:improve_know);
			do remove_desire(predicate:improve_man);
			do remove_desire(predicate:improve_emp);  
    		do add_desire(predicate:idle, strength: 1.0);
       }  
       // improving_emp: same structure and step sizes as improving_man, applied to employees.
       plan improving_emp intention: improve_emp {
       		float difference_cost <- 1 - cost;
       		float difference_emp <- 1- emp;   
	 		my_icon <- improvement_emp;
       		status <- 4;			// one absorption cycle in idling before the next decision
       		if emp < 0 {
       			initial_cost <- initial_cost - 0.025;
       			emp <- emp + 0.05;
       		}else if emp < 0.2 {
       			initial_cost <- initial_cost + 0.1;
       			emp <- emp + 0.2;
       			intitial_in_know <- intitial_in_know + 0.2;
       		}else if emp < 0.5 {
       			initial_cost <- initial_cost + 0.075;
       			emp <- emp + 0.15;
       			intitial_in_know <- intitial_in_know + 0.15;     			
       		}else if emp < 0.75 {
      			initial_cost <- initial_cost + 0.05;
       			emp <- emp + 0.1;
       			intitial_in_know <- intitial_in_know + 0.1;	
       		}else {
       			initial_cost <- initial_cost + 0.025;
       			emp <- emp + 0.05;
       			intitial_in_know <- intitial_in_know + 0.05;
       		}
			do remove_desire(predicate:improve_know);
			do remove_desire(predicate:improve_man);
			do remove_desire(predicate:improve_emp);  
    		do add_desire(predicate:idle, strength: 1.0);
       }  
   
  
  
	/*
	 * formatting of the output
	 * the desire_adopt will be at the same location as the icon but 1 layer higher so it's visible on top of the icon
	 */  
    aspect default {
		draw my_icon size: 400;    	
     	//draw string(outdegree with_precision 2) depth: 1 size: 10050 border: #black color: #black; //desire_adopt
     	draw string(desire_adopt with_precision 2) depth: 1 font:font("Helvetica", 30) rotate: 0  border: #black color: #black; //desire_adopt
    }
}


/*
 * species enterprise parent: org {
 * species medium-sized-enterprise parent: org {
 * species small-business parent: org {
 * species it-startup parent: org {
 * 
 */
species enterprise parent: org {
	int type_org <- 1;														// fixed 1 for enterprise
	float gov_tie_strength <- 0.7;											// Triple Helix: strong government proximity via scale/lobbying (v2.23)
	float gov_leg_multiplier <- 1.0;										// NIS2 essential-entity tier -- highest exposure (v2.23)
	float gov_fin_multiplier <- 0.6;										// large-firm subsidy crowding-out, less effective per unit (v2.23)

	float emp <- rnd(-1.0, 1.0);														// -1 -> 1
	float man <- rnd(-1.0, 1.0); 														// -1 -> 1

 	float gov_fin <- gov_tie_strength*gov_fin_multiplier*gov_subsidy_amount + (1-gov_tie_strength)*rnd(-1.0,1.0);
  	float gov_leg <- gov_tie_strength*gov_leg_multiplier*legal_stringency + (1-gov_tie_strength)*rnd(-1.0,1.0);
   	float pre_cus<- rnd(0.0, 1.0);													// 0 -> 1
   
   	float in_know <- rnd(0.0, 1.0); 													// the initial value will only be knowledge of the company and later combined with human knowledge
   																			// 0 -> 1		
	float in_res <- rnd(0.0, 1.0); 													// 0 -> 1
   	
   	float cost <- rnd(0.0, 1.0); 														// 0 -> 1	initial assignment can change duo to the influence of man/emp to -1 -> 2	
	float funds <- rnd(0.0, 1.0);   													// 0 -> 1  for initial assignment can change duo to gov_fin but will change each 12 cycles by addition of ra 
	float ra <- rnd(0.0, 1.0);     													// R+  {Adjustment weight to the yearly increase of available internal resources. 
																			// 		A higher number implies the company is willing to set aside more money for the process of adoption.
																			//		This number should be > 0.}

    image_file green_lock <- image_file("../includes/Icons/enter_green_lock.png");
    image_file red_lock <- image_file("../includes/Icons/enter_red_lock.png");
    image_file purple_lock <- image_file("../includes/Icons/enter_purple_lock.png");
	image_file improvement <- image_file("../includes/Icons/enter_improv.png");   
	image_file improvement_know <- image_file("../includes/Icons/enter_know.png");  	
	image_file improvement_man <- image_file("../includes/Icons/enter_man.png");  	
	image_file improvement_emp <- image_file("../includes/Icons/enter_emp.png");  	
	image_file waiting <- image_file("../includes/Icons/enter_waiting.png");  	
	image_file my_icon <- red_lock; 
}
species enterprise_medium parent: org {
	int type_org <- 2;														// fixed 1 for enterprise_medium
	float gov_tie_strength <- 0.8;											// Triple Helix: stands in for the research-institution/university role (v2.23)
	float gov_leg_multiplier <- 0.7;										// NIS2 important-entity tier (v2.23)
	float gov_fin_multiplier <- 0.8;										// moderate subsidy effectiveness (v2.23)

	float emp <- rnd(-1.0, 1.0);														// -1 -> 1
	float man <- rnd(-1.0, 1.0); 														// -1 -> 1

 	float gov_fin <- gov_tie_strength*gov_fin_multiplier*gov_subsidy_amount + (1-gov_tie_strength)*rnd(-1.0,1.0);
  	float gov_leg <- gov_tie_strength*gov_leg_multiplier*legal_stringency + (1-gov_tie_strength)*rnd(-1.0,1.0);
   	float pre_cus<- rnd(0.0, 1.0);													// 0 -> 1
   
   	float in_know <- rnd(0.0, 1.0); 													// the initial value will only be knowledge of the company and later combined with human knowledge
   																			// 0 -> 1		
	float in_res <- rnd(0.0, 1.0); 													// 0 -> 1
   	
   	float cost <- rnd(0.0, 1.0); 														// 0 -> 1	initial assignment can change duo to the influence of man/emp to -1 -> 2	
	float funds <- rnd(0.0, 1.0);   													// 0 -> 1  for initial assignment can change duo to gov_fin but will change each 12 cycles by addition of ra 
	float ra <- rnd(0.0, 1.0);     													// R+  {Adjustment weight to the yearly increase of available internal resources. 
																			// 		A higher number implies the company is willing to set aside more money for the process of adoption.
																			//		This number should be > 0.}
	
	image_file green_lock <- image_file("../includes/Icons/middle_green_lock.png");
    image_file red_lock <- image_file("../includes/Icons/middle_red_lock.png");
    image_file purple_lock <- image_file("../includes/Icons/middle_purple_lock.png");
	image_file improvement <- image_file("../includes/Icons/middle_improv.png");   
	image_file improvement_know <- image_file("../includes/Icons/middle_know.png");  	
	image_file improvement_man <- image_file("../includes/Icons/middle_man.png");  	
	image_file improvement_emp <- image_file("../includes/Icons/middle_emp.png");  	
	image_file waiting <- image_file("../includes/Icons/middle_waiting.png");  	
	image_file my_icon <- red_lock; 	
}
species business_small parent: org {
	int type_org <- 3;														// fixed 1 for business_small
	float gov_tie_strength <- 0.4;											// weaker government proximity, matching this type's lower network connectivity elsewhere (v2.23)
	float gov_leg_multiplier <- 0.3;										// NIS2 below-threshold tier -- often exempt or lightly covered (v2.23)
	float gov_fin_multiplier <- 1.2;										// SME-targeted subsidy effectiveness boost (v2.23)

	float emp <- rnd(-1.0, 1.0);														// -1 -> 1
	float man <- rnd(-1.0, 1.0); 														// -1 -> 1

 	float gov_fin <- gov_tie_strength*gov_fin_multiplier*gov_subsidy_amount + (1-gov_tie_strength)*rnd(-1.0,1.0);
  	float gov_leg <- gov_tie_strength*gov_leg_multiplier*legal_stringency + (1-gov_tie_strength)*rnd(-1.0,1.0);
   	float pre_cus<- rnd(0.0, 1.0);													// 0 -> 1
   
   	float in_know <- rnd(0.0, 1.0); 													// the initial value will only be knowledge of the company and later combined with human knowledge
   																			// 0 -> 1		
	float in_res <- rnd(0.0, 1.0); 													// 0 -> 1
   	
   	float cost <- rnd(0.0, 1.0); 														// 0 -> 1	initial assignment can change duo to the influence of man/emp to -1 -> 2	
	float funds <- rnd(0.0, 1.0);   													// 0 -> 1  for initial assignment can change duo to gov_fin but will change each 12 cycles by addition of ra 
	float ra <- rnd(0.0, 1.0);     													// R+  {Adjustment weight to the yearly increase of available internal resources. 
																			// 		A higher number implies the company is willing to set aside more money for the process of adoption.
																			//		This number should be > 0.}
	
	image_file green_lock <- image_file("../includes/Icons/small_green_lock.png");
    image_file red_lock <- image_file("../includes/Icons/small_red_lock.png");
    image_file purple_lock <- image_file("../includes/Icons/small_purple_lock.png");
	image_file improvement <- image_file("../includes/Icons/small_improv.png");   
	image_file improvement_know <- image_file("../includes/Icons/small_know.png");  	
	image_file improvement_man <- image_file("../includes/Icons/small_man.png");  	
	image_file improvement_emp <- image_file("../includes/Icons/small_emp.png");  	
	image_file waiting <- image_file("../includes/Icons/small_waiting.png");  	
	image_file my_icon <- red_lock; 	
}
species startup_it parent: org {
	int type_org <- 4;														// fixed 1 for startup_it
	float gov_tie_strength <- 0.4;											// weaker government proximity, matching this type's lower network connectivity elsewhere (v2.23)
	float gov_leg_multiplier <- 0.3;										// NIS2 below-threshold tier -- often exempt or lightly covered (v2.23)
	float gov_fin_multiplier <- 1.2;										// SME-targeted subsidy effectiveness boost (v2.23)

	float emp <- rnd(-1.0, 1.0);														// -1 -> 1
	float man <- rnd(-1.0, 1.0); 														// -1 -> 1

 	float gov_fin <- gov_tie_strength*gov_fin_multiplier*gov_subsidy_amount + (1-gov_tie_strength)*rnd(-1.0,1.0);
  	float gov_leg <- gov_tie_strength*gov_leg_multiplier*legal_stringency + (1-gov_tie_strength)*rnd(-1.0,1.0);
   	float pre_cus<- rnd(0.0, 1.0);													// 0 -> 1
   
   	float in_know <- rnd(0.0, 1.0); 													// the initial value will only be knowledge of the company and later combined with human knowledge
   																			// 0 -> 1		
	float in_res <- rnd(0.0, 1.0); 													// 0 -> 1
   	
   	float cost <- rnd(0.0, 1.0); 														// 0 -> 1	initial assignment can change duo to the influence of man/emp to -1 -> 2	
	float funds <- rnd(0.0, 1.0);   													// 0 -> 1  for initial assignment can change duo to gov_fin but will change each 12 cycles by addition of ra 
	float ra <- rnd(0.0, 1.0);     													// R+  {Adjustment weight to the yearly increase of available internal resources. 
																			// 		A higher number implies the company is willing to set aside more money for the process of adoption.
																			//		This number should be > 0.}
	
	
	
	image_file green_lock <- image_file("../includes/Icons/start_green_lock.png");
    image_file red_lock <- image_file("../includes/Icons/start_red_lock.png");
    image_file purple_lock <- image_file("../includes/Icons/start_purple_lock.png");
	image_file improvement <- image_file("../includes/Icons/start_improv.png");   
	image_file improvement_know <- image_file("../includes/Icons/start_know.png");  	
	image_file improvement_man <- image_file("../includes/Icons/start_man.png");  	
	image_file improvement_emp <- image_file("../includes/Icons/start_emp.png");  	
	image_file waiting <- image_file("../includes/Icons/start_waiting.png");  	
	image_file my_icon <- red_lock; 	
}


species socialLinkRepresentation{
    org origin;
    agent destination;
    rgb my_color;
    
    aspect base{
        draw line([origin,destination],50.0) color: my_color end_arrow:10;
    }
}

/*
 * =====================================================================================
 *  EXPERIMENTS
 * =====================================================================================
 *  Agent_Model: interactive single run with visualisation.
 *  All other experiments are native `type: batch` experiments for headless execution
 *  (seeded repeats, explicit parameter levels via `among:`, `until:` stop condition). Most batch
 *  experiments hold exactly one parameter combination; Scenarios 3, 4 and 5 sweep a few levels.
 *  Every experiment writes to its own output files.
 *  enable_link_visualization is switched off in batch runs, as nothing is displayed.
 *  Experiments marked with a quote implement the scenarios proposed in the concept
 *  ("Future simulation scenarios").
 * =====================================================================================
 */

// --- interactive/visual run: unchanged single-simulation exploration ---
experiment Agent_Model type: gui {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale min: 1 max: 4;
    parameter "Enable link visualization" var: enable_link_visualization;

    init {
        trajectory_output_path <- model_version + "_gui_run.csv";	// is_batch stays false -- uses the file_exists() header check
    }

    output {
        display chart refresh: every(1#cycle) {
            chart "Adopted" type: series {
                data "#Agents on PQS" value: finished_adopting color: #black;
            }
        }
        display map {
            species dot aspect: geom;
            species org aspect: default;
            species enterprise aspect: default;
            species enterprise_medium aspect: default;
            species business_small aspect: default;
            species startup_it aspect: default;
            species socialLinkRepresentation aspect: base;
        }
    }
}

/*
 * SCENARIO 1 — Random runs (baseline)
 * "Multiple random distributed values ... used for multiple simulations. A detailed
 *  statistical analysis can then be used to identify valuable information about the
 *  behaviour of agents and overall performance over a widespread distribution."
 * All internal/external factors keep their default rnd() initialisation; this batch
 * just repeats that many times with different seeds and records the diffusion curve.
 */
experiment Scenario_1_RandomBaseline type: batch repeat: 300 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:300 = 300 simulations total.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        // rng set explicitly in every experiment for reproducibility (v2.27).
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1_random_baseline.csv";
    }
}

/*
 * SCENARIO 1B — High-resolution baseline (v2.16)
 * Baseline conditions (no interventions) with the 1%-resolution diffusion-curve log, used to
 * determine the shape of the diffusion curve. n = 150.
 */
experiment Scenario_1B_HighResolutionBaseline type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:150 = 150 simulations total.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1b_highres_baseline.csv";
    }
}

/*
 * SCENARIO 1C — desire_adopt_constant comparison (v2.18 / v2.19)
 * Six experiments, one value each: 1.5 (concept specification), 1.75, 2.0, 3.0, 3.5, 4.0.
 * Monte Carlo estimates of P(desire_adopt > 0.5) at cycle 0: approx. 56% at 1.5, 16% at 3.0,
 * 8% at 3.5, 3% at 4.0. Tests how strongly the constant controls the initial adoption surge and
 * whether full adoption is still reached in reasonable time. Uses the 1% curve log.
 */
experiment Scenario_1C_ConstantCompare_1_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant 1.5, the concept specification) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant1_5.csv";
    }
}
experiment Scenario_1C_ConstantCompare_1_75 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant fixed at 1.75, midpoint) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [1.75];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant1_75.csv";
    }
}
experiment Scenario_1C_ConstantCompare_2_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant fixed at 2.0, the original pre-v2.0 implementation's value) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant2_0.csv";
    }
}

/*
 * SCENARIO 1C, continued (v2.19) — higher values (3.0 / 3.5 / 4.0), see above.
 */
experiment Scenario_1C_ConstantCompare_3_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant fixed at 3.0, ~16% predicted immediate-adoption rate) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [3.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant3_0.csv";
    }
}
experiment Scenario_1C_ConstantCompare_3_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant fixed at 3.5, ~8% predicted immediate-adoption rate) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [3.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant3_5.csv";
    }
}
experiment Scenario_1C_ConstantCompare_4_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (constant fixed at 4.0, ~3% predicted immediate-adoption rate) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Eq.38 constant" var: desire_adopt_constant among: [4.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1c_constant4_0.csv";
    }
}

/*
 * SCENARIO 1D — Fixed starting inertia (v2.20)
 * One shared starting_inertia value per experiment (0 / 2 / 5 / 10 / 20). Tests whether a later
 * first decision changes the shape of the diffusion curve or only delays it. The constant is not
 * set here, so these experiments use the global default desire_adopt_constant. Uses the 1%
 * curve log.
 */
experiment Scenario_1D_InertiaCompare_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (starting_inertia fixed at 0.0, the current/original behaviour) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [0.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia0.csv";
    }
}
experiment Scenario_1D_InertiaCompare_2 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (starting_inertia fixed at 2.0) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia2.csv";
    }
}
experiment Scenario_1D_InertiaCompare_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (starting_inertia fixed at 5.0) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [5.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia5.csv";
    }
}
experiment Scenario_1D_InertiaCompare_10 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (starting_inertia fixed at 10.0) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [10.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia10.csv";
    }
}
experiment Scenario_1D_InertiaCompare_20 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (starting_inertia fixed at 20.0) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [20.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia20.csv";
    }
}

/*
 * SCENARIO 1D, continued (v2.21) — finer sweep (7 / 8 / 9 / 11 / 12 / 15) around the
 * non-monotonic result observed at starting_inertia = 10 (mean completion far above both
 * neighbouring values, driven by a long tail rather than a shift of the majority).
 */
experiment Scenario_1D_InertiaCompare_7 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [7.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia7.csv";
    }
}
experiment Scenario_1D_InertiaCompare_8 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [8.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia8.csv";
    }
}
experiment Scenario_1D_InertiaCompare_9 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [9.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia9.csv";
    }
}
experiment Scenario_1D_InertiaCompare_11 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [11.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia11.csv";
    }
}
experiment Scenario_1D_InertiaCompare_12 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [12.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia12.csv";
    }
}
experiment Scenario_1D_InertiaCompare_15 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia" var: starting_inertia among: [15.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1d_inertia15.csv";
    }
}

/*
 * SCENARIO 1E — Random per-agent starting inertia (v2.21)
 * Each agent draws its own starting inertia from [0, starting_inertia]
 * (randomize_starting_inertia <- true), so agents become eligible to decide at different
 * times. Upper bounds 5 / 10 / 20 match a subset of Scenario 1D for a fixed-vs-random comparison.
 */
experiment Scenario_1E_RandomInertiaCompare_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia (upper bound)" var: starting_inertia among: [5.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        randomize_starting_inertia <- true;
        trajectory_output_path <- model_version + "_scenario1e_randominertia5.csv";
    }
}
experiment Scenario_1E_RandomInertiaCompare_10 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia (upper bound)" var: starting_inertia among: [10.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        randomize_starting_inertia <- true;
        trajectory_output_path <- model_version + "_scenario1e_randominertia10.csv";
    }
}
experiment Scenario_1E_RandomInertiaCompare_20 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Starting inertia (upper bound)" var: starting_inertia among: [20.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        randomize_starting_inertia <- true;
        trajectory_output_path <- model_version + "_scenario1e_randominertia20.csv";
    }
}

/*
 * SCENARIO 1F — Type-differentiated starting inertia: two competing hypotheses (v2.22)
 * Same [0,5] vs [0,15] contrast in both directions:
 *  - Bureaucracy_LargeSlow: large organisations [0,15], SMEs [0,5]
 *    (more approval layers and stakeholders slow large organisations).
 *  - ResourceBuffer_SMESlow: SMEs [0,15], large organisations [0,5]
 *    (SMEs first need to build up financial resources).
 * The resulting SME-large gap is compared with the gap produced by network connectivity alone.
 */
experiment Scenario_1F_Bureaucracy_LargeSlow type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // Large orgs draw from [0,15] (slow/bureaucratic), SMEs from [0,5] (agile).
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Large-org starting inertia (upper bound)" var: starting_inertia_large among: [15.0];
    parameter "SME starting inertia (upper bound)" var: starting_inertia_sme among: [5.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        randomize_starting_inertia <- true;
        differentiate_inertia_by_type <- true;
        trajectory_output_path <- model_version + "_scenario1f_bureaucracy_largeslow.csv";
    }
}
experiment Scenario_1F_ResourceBuffer_SMESlow type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // SMEs draw from [0,15] (need to build up resources first), large orgs from [0,5] (existing slack).
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Large-org starting inertia (upper bound)" var: starting_inertia_large among: [5.0];
    parameter "SME starting inertia (upper bound)" var: starting_inertia_sme among: [15.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        randomize_starting_inertia <- true;
        differentiate_inertia_by_type <- true;
        trajectory_output_path <- model_version + "_scenario1f_resourcebuffer_smeslow.csv";
    }
}

/*
 * SCENARIO 1G — Government actor check (v2.23)
 * Two conditions: no intervention (must reproduce the baseline, confirming the gov_fin/gov_leg
 * blend is neutral when gov_subsidy_amount = legal_stringency = 0) and full intervention
 * (subsidy = stringency = 1, both desire weights 2.0).
 */
experiment Scenario_1G_GovAgentTest_NoIntervention type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount" var: gov_subsidy_amount among: [0.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario1g_govagent_nointervention.csv";
    }
}
experiment Scenario_1G_GovAgentTest_FullIntervention type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount" var: gov_subsidy_amount among: [1.0];
    parameter "Financial-incentive desire weight" var: gov_desire_weight_govfin among: [2.0];
    parameter "Legal-mandate desire weight" var: gov_desire_weight_govleg among: [2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario1g_govagent_fullintervention.csv";
    }
}

/*
 * SCENARIO 1H — Market-pressure diagnostic (v2.24)
 * Same parameters as Scenario_1G_GovAgentTest_FullIntervention, with trajectory_log_interval = 1,
 * to follow cycle by cycle which group's adopters drive the shared pre_mar signal in the first
 * cycles (diagnostic columns of log_trajectory).
 */
experiment Scenario_1H_Diagnostic_PreMarTrajectory type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount" var: gov_subsidy_amount among: [1.0];
    parameter "Financial-incentive desire weight" var: gov_desire_weight_govfin among: [2.0];
    parameter "Legal-mandate desire weight" var: gov_desire_weight_govleg among: [2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_log_interval <- 1;
        trajectory_output_path <- model_version + "_scenario1h_diagnostic_premar.csv";
    }
}


/*
 * SCENARIO 1I — Baseline ensemble (v2.28)
 * pre_mar is a shared, self-reinforcing signal, so a small early advantage of one group can tip
 * the whole run (path dependence). Within one experiment, replicates tend to agree on which
 * group finishes first, while independent repetitions of the same experiment can tip the other
 * way; a single pooled mean is therefore not a stable estimate of the SME-large gap.
 * This scenario runs 20 independent invocations of the baseline (repeat: 30 each) and reports the
 * distribution across invocations (share of invocations in which each group finishes first, and
 * the gap conditional on the winner). Each invocation is a separate experiment with its own
 * output file, so results can be attributed without per-invocation parameters in the XML plan.
 */

experiment Scenario_1I_Ensemble_01 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 1 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_01.csv";
    }
}

experiment Scenario_1I_Ensemble_02 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 2 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_02.csv";
    }
}

experiment Scenario_1I_Ensemble_03 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 3 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_03.csv";
    }
}

experiment Scenario_1I_Ensemble_04 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 4 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_04.csv";
    }
}

experiment Scenario_1I_Ensemble_05 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 5 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_05.csv";
    }
}

experiment Scenario_1I_Ensemble_06 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 6 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_06.csv";
    }
}

experiment Scenario_1I_Ensemble_07 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 7 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_07.csv";
    }
}

experiment Scenario_1I_Ensemble_08 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 8 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_08.csv";
    }
}

experiment Scenario_1I_Ensemble_09 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 9 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_09.csv";
    }
}

experiment Scenario_1I_Ensemble_10 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 10 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_10.csv";
    }
}

experiment Scenario_1I_Ensemble_11 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 11 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_11.csv";
    }
}

experiment Scenario_1I_Ensemble_12 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 12 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_12.csv";
    }
}

experiment Scenario_1I_Ensemble_13 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 13 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_13.csv";
    }
}

experiment Scenario_1I_Ensemble_14 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 14 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_14.csv";
    }
}

experiment Scenario_1I_Ensemble_15 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 15 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_15.csv";
    }
}

experiment Scenario_1I_Ensemble_16 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 16 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_16.csv";
    }
}

experiment Scenario_1I_Ensemble_17 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 17 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_17.csv";
    }
}

experiment Scenario_1I_Ensemble_18 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 18 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_18.csv";
    }
}

experiment Scenario_1I_Ensemble_19 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 19 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_19.csv";
    }
}

experiment Scenario_1I_Ensemble_20 type: batch repeat: 30 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination x repeat:30 = 30 simulations. Independent invocation 20 of 20.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario1i_ensemble_20.csv";
    }
}

/*
 * SCENARIO 2 — Improved runs
 * "Based on knowledge gained from previous random runs, weights and values ... will be set
 *  to prior identified successful or interesting value ranges."
 * Joint variation of the financial-cost weight (override_d_prob_cost) and the knowledge weight
 * (override_d_in_know) at 0.5 / 1.0 / 1.5 each: nine experiments, one combination each,
 * repeat: 100.
 */

experiment Scenario_2_ProbCost0_5_InKnow0_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [0.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost0_5_inknow0_5.csv";
    }
}

experiment Scenario_2_ProbCost0_5_InKnow1_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [0.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost0_5_inknow1_0.csv";
    }
}

experiment Scenario_2_ProbCost0_5_InKnow1_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [0.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost0_5_inknow1_5.csv";
    }
}

experiment Scenario_2_ProbCost1_0_InKnow0_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.0];
    parameter "Knowledge desire weight" var: override_d_in_know among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_0_inknow0_5.csv";
    }
}

experiment Scenario_2_ProbCost1_0_InKnow1_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.0];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_0_inknow1_0.csv";
    }
}

experiment Scenario_2_ProbCost1_0_InKnow1_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.0];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_0_inknow1_5.csv";
    }
}

experiment Scenario_2_ProbCost1_5_InKnow0_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_5_inknow0_5.csv";
    }
}

experiment Scenario_2_ProbCost1_5_InKnow1_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_5_inknow1_0.csv";
    }
}

experiment Scenario_2_ProbCost1_5_InKnow1_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (both weights fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-cost desire weight" var: override_d_prob_cost among: [1.5];
    parameter "Knowledge desire weight" var: override_d_in_know among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario2_probcost1_5_inknow1_5.csv";
    }
}


/*
 * SCENARIO 3 — Governmental influence (financial + legal)
 *  - gov_subsidy_amount injects funds via fin_matching (concept Eq.35) and, mirrored into
 *    legal_stringency, sets the strength of the shared government signal in gov_fin / gov_leg.
 *  - gov_desire_weight_govfin / gov_desire_weight_govleg set how strongly financial incentive and
 *    legal mandate move desire_adopt (concept Eq.38).
 * Three experiments (3A/3B/3C: subsidy 0.0 / 0.5 / 1.0), each sweeping both desire weights at
 * 1.0 / 2.0 (4 combinations x repeat: 100).
 */
experiment Scenario_3A_GovernmentInfluence_Subsidy0_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 2x2=4 combinations (govfin x govleg sweep, subsidy fixed at 0.0) x repeat:100 = 400 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Financial-incentive desire weight" var: gov_desire_weight_govfin among: [1.0, 2.0];
    parameter "Legal-mandate desire weight" var: gov_desire_weight_govleg among: [1.0, 2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario3a_government_influence_subsidy0_0.csv";
    }
}
experiment Scenario_3B_GovernmentInfluence_Subsidy0_5 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 2x2=4 combinations (govfin x govleg sweep, subsidy fixed at 0.5) x repeat:100 = 400 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.5];
    parameter "Financial-incentive desire weight" var: gov_desire_weight_govfin among: [1.0, 2.0];
    parameter "Legal-mandate desire weight" var: gov_desire_weight_govleg among: [1.0, 2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario3b_government_influence_subsidy0_5.csv";
    }
}
experiment Scenario_3C_GovernmentInfluence_Subsidy1_0 type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 2x2=4 combinations (govfin x govleg sweep, subsidy fixed at 1.0) x repeat:100 = 400 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Financial-incentive desire weight" var: gov_desire_weight_govfin among: [1.0, 2.0];
    parameter "Legal-mandate desire weight" var: gov_desire_weight_govleg among: [1.0, 2.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario3c_government_influence_subsidy1_0.csv";
    }
}

/*
 * SCENARIO 4 — Top-down influence by companies
 * "One or few big companies with a positive social link to multiple agents ... can spread
 *  information and influence adoption decisions."
 * Implemented via scenario_topdown: at init, a small number of `enterprise` agents are
 * pushed toward near-maximal internal factors (emp/man/in_know/in_res close to 1), which
 * clears their inertia fastest and — via the existing outdegree/pressure mechanic — raises
 * pre_mar for everyone once they adopt. This approximates the concept's intent with the
 * mechanics already in the model rather than additional social-link machinery.
 * nb_topdown_hubs = 1..5, repeat: 100.
 */
experiment Scenario_4_TopDownInfluence type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 5 combinations x repeat:100 = 500 simulations total.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Number of top-down hub companies" var: nb_topdown_hubs among: [1, 2, 3, 4, 5];
    init {
        enable_link_visualization <- false;
        scenario_topdown <- true;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario4_topdown_influence.csv";
    }
}

/*
 * SCENARIO 5 — Bottom-up influence by companies
 * "Multiple adoption-interested companies try to influence more complex organisations ...
 *  small companies characterised with high values in internal factors."
 * Implemented via scenario_bottomup: a configurable share of business_small/startup_it
 * agents are initialised with high internal-factor values to represent early, motivated
 * adopters generating market pressure from the bottom.
 * bottomup_eager_share = 0.2 / 0.4 / 0.6 / 0.8, repeat: 100.
 */
experiment Scenario_5_BottomUpInfluence type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 4 combinations x repeat:100 = 400 simulations total.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Share of eager small adopters" var: bottomup_eager_share among: [0.2, 0.4, 0.6, 0.8];
    init {
        enable_link_visualization <- false;
        scenario_bottomup <- true;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario5_bottomup_influence.csv";
    }
}

/*
 * SCENARIO 6 — One-factor-at-a-time sensitivity screen (extension, not in the concept)
 * Identifies which weight in desire_adopt (concept Eq.38) diffusion speed is most sensitive to.
 * 27 experiments: nine weights (6A-6I) x three levels (0.5 / 1.0 / 1.5), repeat: 150 each, all
 * other weights at 1.0. The 1.0-level experiment of each weight is therefore a baseline point.
 * A global method (`method: morris` / `method: sobol`) would give variance-based sensitivity
 * indices and is a possible extension.
 */

experiment Scenario_6A_Sensitivity_prob_cost_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Cost/funds weight (d_prob_cost)" var: override_d_prob_cost among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6a_sensitivity_prob_cost_0_5.csv";
    }
}

experiment Scenario_6A_Sensitivity_prob_cost_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Cost/funds weight (d_prob_cost)" var: override_d_prob_cost among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6a_sensitivity_prob_cost_1_0.csv";
    }
}

experiment Scenario_6A_Sensitivity_prob_cost_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Cost/funds weight (d_prob_cost)" var: override_d_prob_cost among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6a_sensitivity_prob_cost_1_5.csv";
    }
}

experiment Scenario_6B_Sensitivity_in_know_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Knowledge weight (d_in_know)" var: override_d_in_know among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6b_sensitivity_in_know_0_5.csv";
    }
}

experiment Scenario_6B_Sensitivity_in_know_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Knowledge weight (d_in_know)" var: override_d_in_know among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6b_sensitivity_in_know_1_0.csv";
    }
}

experiment Scenario_6B_Sensitivity_in_know_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Knowledge weight (d_in_know)" var: override_d_in_know among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6b_sensitivity_in_know_1_5.csv";
    }
}

experiment Scenario_6C_Sensitivity_precus_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Customer-pressure weight (d_precus)" var: override_d_precus among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6c_sensitivity_precus_0_5.csv";
    }
}

experiment Scenario_6C_Sensitivity_precus_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Customer-pressure weight (d_precus)" var: override_d_precus among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6c_sensitivity_precus_1_0.csv";
    }
}

experiment Scenario_6C_Sensitivity_precus_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Customer-pressure weight (d_precus)" var: override_d_precus among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6c_sensitivity_precus_1_5.csv";
    }
}

experiment Scenario_6D_Sensitivity_premar_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Market-pressure weight (d_premar)" var: override_d_premar among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6d_sensitivity_premar_0_5.csv";
    }
}

experiment Scenario_6D_Sensitivity_premar_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Market-pressure weight (d_premar)" var: override_d_premar among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6d_sensitivity_premar_1_0.csv";
    }
}

experiment Scenario_6D_Sensitivity_premar_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Market-pressure weight (d_premar)" var: override_d_premar among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6d_sensitivity_premar_1_5.csv";
    }
}

experiment Scenario_6E_Sensitivity_com_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Social-link weight (d_com)" var: override_d_com among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6e_sensitivity_com_0_5.csv";
    }
}

experiment Scenario_6E_Sensitivity_com_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Social-link weight (d_com)" var: override_d_com among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6e_sensitivity_com_1_0.csv";
    }
}

experiment Scenario_6E_Sensitivity_com_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Social-link weight (d_com)" var: override_d_com among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6e_sensitivity_com_1_5.csv";
    }
}

experiment Scenario_6F_Sensitivity_man_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Management weight (d_man)" var: override_d_man among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6f_sensitivity_man_0_5.csv";
    }
}

experiment Scenario_6F_Sensitivity_man_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Management weight (d_man)" var: override_d_man among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6f_sensitivity_man_1_0.csv";
    }
}

experiment Scenario_6F_Sensitivity_man_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Management weight (d_man)" var: override_d_man among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6f_sensitivity_man_1_5.csv";
    }
}

experiment Scenario_6G_Sensitivity_emp_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Employee weight (d_emp)" var: override_d_emp among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6g_sensitivity_emp_0_5.csv";
    }
}

experiment Scenario_6G_Sensitivity_emp_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Employee weight (d_emp)" var: override_d_emp among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6g_sensitivity_emp_1_0.csv";
    }
}

experiment Scenario_6G_Sensitivity_emp_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Employee weight (d_emp)" var: override_d_emp among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6g_sensitivity_emp_1_5.csv";
    }
}

experiment Scenario_6H_Sensitivity_govfin_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-incentive weight (d_govfin)" var: gov_desire_weight_govfin among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6h_sensitivity_govfin_0_5.csv";
    }
}

experiment Scenario_6H_Sensitivity_govfin_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-incentive weight (d_govfin)" var: gov_desire_weight_govfin among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6h_sensitivity_govfin_1_0.csv";
    }
}

experiment Scenario_6H_Sensitivity_govfin_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Financial-incentive weight (d_govfin)" var: gov_desire_weight_govfin among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6h_sensitivity_govfin_1_5.csv";
    }
}

experiment Scenario_6I_Sensitivity_govleg_0_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 0.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Legal-mandate weight (d_govleg)" var: gov_desire_weight_govleg among: [0.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6i_sensitivity_govleg_0_5.csv";
    }
}

experiment Scenario_6I_Sensitivity_govleg_1_0 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.0) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Legal-mandate weight (d_govleg)" var: gov_desire_weight_govleg among: [1.0];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6i_sensitivity_govleg_1_0.csv";
    }
}

experiment Scenario_6I_Sensitivity_govleg_1_5 type: batch repeat: 150 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (weight fixed at 1.5) x repeat:150 = 150 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Legal-mandate weight (d_govleg)" var: gov_desire_weight_govleg among: [1.5];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        trajectory_output_path <- model_version + "_scenario6i_sensitivity_govleg_1_5.csv";
    }
}


/*
 * SCENARIO 7 — Government x top-down / bottom-up interaction (extension, not in the concept)
 * Tests whether the effect of government intervention depends on whether diffusion is already
 * driven by market-leading hubs (top-down) or by many motivated small adopters (bottom-up).
 * 2 x 2 x 2 x 2 design (subsidy 0 / 1, legal weight 1 / 2, top-down off/on, bottom-up off/on):
 * sixteen experiments, one combination each, repeat: 100.
 */

experiment Scenario_7_Subsidy0_0_Govleg1_0_TopdownOff_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg1_0_topdownoff_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg1_0_TopdownOff_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg1_0_topdownoff_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg1_0_TopdownOn_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg1_0_topdownon_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg1_0_TopdownOn_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg1_0_topdownon_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg2_0_TopdownOff_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg2_0_topdownoff_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg2_0_TopdownOff_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg2_0_topdownoff_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg2_0_TopdownOn_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg2_0_topdownon_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy0_0_Govleg2_0_TopdownOn_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [0.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy0_0_govleg2_0_topdownon_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg1_0_TopdownOff_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg1_0_topdownoff_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg1_0_TopdownOff_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg1_0_topdownoff_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg1_0_TopdownOn_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg1_0_topdownon_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg1_0_TopdownOn_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [1.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg1_0_topdownon_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg2_0_TopdownOff_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg2_0_topdownoff_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg2_0_TopdownOff_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [false];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg2_0_topdownoff_bottomupon.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg2_0_TopdownOn_BottomupOff type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [false];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg2_0_topdownon_bottomupoff.csv";
    }
}

experiment Scenario_7_Subsidy1_0_Govleg2_0_TopdownOn_BottomupOn type: batch repeat: 100 until: (finished_adopting = organisations) or (cycle = max_cycle_safety_cap) {
    // 1 combination (all four parameters fixed) x repeat:100 = 100 simulations.
    parameter "Agent count scale (30 x scale)" var: agent_count_scale init: 2;
    parameter "Government subsidy amount (fin_matching)" var: gov_subsidy_amount among: [1.0];
    parameter "Government legal-mandate weight" var: gov_desire_weight_govleg among: [2.0];
    parameter "Top-down scenario active" var: scenario_topdown among: [true];
    parameter "Bottom-up scenario active" var: scenario_bottomup among: [true];
    init {
        enable_link_visualization <- false;
        is_batch <- true;
        rng <- "mersenne";
        legal_stringency <- gov_subsidy_amount;
        trajectory_output_path <- model_version + "_scenario7_subsidy1_0_govleg2_0_topdownon_bottomupon.csv";
    }
}
