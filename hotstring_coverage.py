"""Check full hotstring triggers directly against beginning/middle/end rules.

Actual source examples:
    :BCTk-1*:inetr::inter    -> beginning rule inetr -> inter
    :BCTk-1?:atde::ated      -> ending rule atde -> ated
    :BCTk-1?*:aiton::ation  -> middle rule aiton -> ation
    ::serializaiton::serialization -> individual middle-rule example
    ::inetrnet::internet    -> individual generated whole-word rule
    ::simulatde::simulated  -> another individual generated whole-word rule

The stored containers passed between functions are:
    definitions      -> parsed dictionaries from one input file.
    rules            -> accepted start/middle/end dictionaries, with kind and order.
    whole_word_rules -> individual typo/correction dictionaries.
    decisions        -> one result dictionary per whole-word rule, referring to a rule or None.

For example, omitting source metadata:
    rule  = {"trigger": "inetr", "replacement": "inter", "kind": "start", ...}
    whole_word_rule = {"trigger": "inetrnet", "replacement": "internet", ...}
The checker takes that whole-word rule and checks every supplied rule directly.
The beginning helper uses startswith() and removeprefix(); the ending helper
uses endswith() and removesuffix(). The middle helper uses replace(..., 1)
for the first matching occurrence anywhere. The complete output must equal the whole-word rule's
expected correction before the whole-word rule is marked covered.

main() connects the readers and checker, writes GeneratedWords_filtered.ahk,
and prints counts. The original GeneratedWords.ahk is left unchanged.
Matching is literal and case-sensitive. Inherited options, include expansion
and backtick-escaped lines are outside the matcher; unprocessed lines are kept.
"""

from pathlib import Path
import re


def _apply_end(rule, text):
    """Return the complete word obtained from one ending-rule dictionary.

    Example inputs:
        rule: {"trigger": "atde", "replacement": "ated", ...}
        text: "simulatde"
    The function returns "simul" + "ated" = "simulated". The caller stores that
    string in corrected and compares it with the current whole-word rule's replacement.
    The rule dictionary and original whole-word rule dictionary are not changed.
    """
    # The ending example retrieves "atde" from the supplied rule dictionary.
    trigger = rule["trigger"]
    # For text="simulatde": endswith("atde") is True.
    if text.endswith(trigger):
        # "simulatde".removesuffix("atde") returns "simul".
        # Adding "ated" returns "simulated".
        return text.removesuffix(trigger) + rule["replacement"]
    # A nonmatching ending gives the caller None rather than corrected text.
    return None


def _apply_middle(rule, text):
    """Replace the first occurrence of one middle-rule trigger anywhere.

    Example inputs:
        rule: {"trigger": "aiton", "replacement": "ation", ...}
        text: "serializaiton"
    The function returns "serialization". The ?* rule permits a match anywhere,
    including the beginning or ending; it is not restricted to the interior.
    Only the first occurrence is replaced, and the input records stay unchanged.
    """
    trigger = rule["trigger"]
    # The complete trigger "aiton" occurs in "serializaiton".
    if trigger in text:
        # The final argument 1 limits replacement to the first occurrence.
        return text.replace(trigger, rule["replacement"], 1)
    # No occurrence gives the caller None.
    return None


def _apply_start(rule, text):
    """Return the complete word obtained from one beginning-rule dictionary.

    Example inputs:
        rule: {"trigger": "inetr", "replacement": "inter", ...}
        text: "inetrnet"
    The function returns "inter" + "net" = "internet". The caller stores that
    string in corrected. If the trigger is not at the beginning, return None.
    The function does not change rule, whole_word_rules or any input file.
    """
    # The beginning example retrieves "inetr" from the rule dictionary.
    trigger = rule["trigger"]
    # For text="inetrnet": startswith("inetr") is True.
    if text.startswith(trigger):
        # "inetrnet".removeprefix("inetr") returns "net".
        # Adding "inter" before "net" returns "internet".
        return rule["replacement"] + text.removeprefix(trigger)
    # A nonmatching beginning gives the caller None.
    return None


def _read_definitions(path):
    """Create the dictionaries that the two public readers subsequently select.

    For :BCTk-1*:inetr::inter, one dictionary has:
        {"options": "BCTk-1*", "trigger": "inetr", "replacement": "inter", ...}
    For ::inetrnet::internet, one dictionary has:
        {"options": "", "trigger": "inetrnet", "replacement": "internet", ...}
    The actual dictionaries also contain line, source and raw_line fields.

    definitions is the list of these dictionaries for one input file. This helper
    does not yet classify them into rule kinds or individual whole-word rules. That is done
    by read_current_rules() and read_generated_word_rules(), respectively.
    """
    # source identifies one supplied file, not the entire collection of files.
    source = Path(path)
    # text holds the decoded file contents; any UTF-8 BOM is removed.
    text = source.read_bytes().decode("utf-8-sig")
    # The per-file parsed-record container starts as definitions = [].
    definitions = []
    # For the generated example, raw_line includes "::inetrnet::internet"
    # and its newline. line_idx supplies its actual source line number.
    for line_idx, raw_line in enumerate(text.splitlines(keepends=True), start=1):
        # line becomes "::inetrnet::internet"; raw_line still has its newline.
        # The parsed text and the original source-line bytes are kept separately.
        line = raw_line.rstrip("\r\n")
        # A blank line or "; explanation" creates no dictionary.
        if not line.strip() or line.lstrip().startswith(";"):
            continue
        # A line with an AHK backtick escape is outside this literal parser.
        if "\x60" in line:
            continue

        # Illustrative input "::typo::correct ; note" becomes "::typo::correct",
        # so " ; note" is not stored as part of the replacement.
        line = re.split(r"\s+;", line, maxsplit=1)[0]
        # For "::inetrnet::internet", groups 1/2/3 are "", "inetrnet", "internet".
        # For ":BCTk-1*:inetr::inter", they are "BCTk-1*", "inetr", "inter".
        match = re.match(r"^:([^:]*):(.+?)::(.*)$", line)
        # Non-hotstring source has no match; "::sign::" has an empty third group.
        # Neither is a one-line replacement dictionary for this reader.
        if match is None or not match.group(3):
            continue
        # The generated example adds {"options": "", "trigger": "inetrnet",
        # "replacement": "internet", ...} to definitions. The fields below also
        # retain its file identity, line number and original source-line bytes.
        definitions.append({
            "line"       : line_idx,
            "options"    : match.group(1),
            "raw_line"   : raw_line.encode("utf-8"),
            "replacement": match.group(3),
            "source"     : str(source),
            # This is where the actual typo "inetrnet" enters the stored dictionary.
            "trigger"    : match.group(2),
        })
    # Return this file's dictionary list to the calling public reader.
    return definitions


def find_covered_word_rules(whole_word_rules, rules):
    """Check each complete whole_word_rule directly against the supplied start/middle/end rules.

    Example whole-word rule:
        {"trigger": "inetrnet", "replacement": "internet", ...}
    Example rule:
        {"kind": "start", "trigger": "inetr", "replacement": "inter", ...}

    The beginning helper directly checks "inetrnet".startswith("inetr").
    It returns "inter" + "net" = "internet", which equals the whole-word rule's target.
    The middle helper similarly replaces aiton -> ation in serializaiton,
    returning serialization. No shorter pieces are generated or looked up.

    Each returned decision refers to the original whole-word rule and its selected rule.
    When several rules give the exact target, retain the lowest rule order.
    This checks positional coverage only and does not modify any AHK file.
    """
    decisions = []
    for whole_word_rule in whole_word_rules:
        # The whole typo is "inetrnet"; its expected correction is "internet".
        best_rule = None
        text = whole_word_rule["trigger"]

        # Check the complete trigger from each real rule against the whole word.
        # For the inetr rule, test "inetrnet".startswith("inetr") directly.
        for rule in rules:
            if rule["kind"] == "start":
                # The helper returns "inter" + "net" = "internet", or None
                # when the whole rule trigger is not at the beginning.
                corrected = _apply_start(rule, text)
            elif rule["kind"] == "middle":
                # The complete trigger "aiton" appears in "serializaiton";
                # replacing its first occurrence returns "serialization".
                corrected = _apply_middle(rule, text)
            elif rule["kind"] == "end":
                # Ending example: "simulatde".endswith("atde") is True;
                # the helper returns "simul" + "ated" = "simulated".
                corrected = _apply_end(rule, text)
            else:
                # A caller-supplied unknown kind cannot establish coverage.
                continue

            # A nonmatch returns None. A match must still reproduce the
            # recorded correction exactly: "internet" == "internet".
            if corrected != whole_word_rule["replacement"]:
                continue

            # Preserve the original selection rule if several patterns work:
            # keep the rule with the lowest supplied order.
            if best_rule is None or rule["order"] < best_rule["order"]:
                best_rule = rule

        # Store references to the same whole-word rule and pattern dictionaries, not copies.
        # No exact result leaves covered=False and rule=None.
        decisions.append({
            "covered": best_rule is not None,
            "whole_word_rule": whole_word_rule,
            "rule": best_rule,
        })
    return decisions


def main():
    """Read, compare, and write a filtered copy containing uncovered lines.

    pattern_paths contains Paths for the main rule file and screened rule file.
    read_current_rules(pattern_paths) returns the rules list. generated_path names
    GeneratedWords.ahk, whose individual dictionaries become the whole_word_rules list.
    find_covered_word_rules(whole_word_rules, rules) receives those existing lists and returns
    decisions, with one result dictionary per whole-word rule.

    Illustrative decisions with covered=[True, False, True] would produce a count
    of 2. The actual count is computed from the real returned decisions at runtime.
    write_filtered_word_rules() then omits covered source line numbers from a new
    output file and copies every other original line, including unprocessed lines.
    """
    # For this module in Programs/hotstring-rule-audit, base_dir is Programs.
    base_dir       = Path(__file__).resolve().parent.parent
    # The output is a separate file beside the original GeneratedWords.ahk.
    filtered_path  = base_dir / "GeneratedWords_filtered.ahk"
    # This Path identifies the file of individual whole-word rules.
    generated_path = base_dir / "GeneratedWords.ahk"
    # This list contains the two rule-file Paths, in the order to read them.
    # The list is explicit; read_current_rules() does not follow #include.
    pattern_paths  = [
        base_dir / "AutoCorrect_Sept5.ahk",
        base_dir / "GeneratedWords_ScreenedRules.ahk",
    ]

    # rules receives start/middle/end dictionaries such as
    # {"trigger": "inetr", "replacement": "inter", "kind": "start", ...}.
    rules            = read_current_rules(pattern_paths)
    # whole_word_rules receives individual dictionaries such as
    # {"trigger": "inetrnet", "replacement": "internet", ...}.
    whole_word_rules = read_generated_word_rules(generated_path)
    # The existing lists are passed without copying. The returned decisions
    # list links each whole_word_rule dictionary to a selected rule dictionary or None.
    decisions = find_covered_word_rules(whole_word_rules, rules)

    # Begin the summary count at zero; none of the source containers is changed.
    covered_count = 0
    # Illustratively, covered values [True, False, True] increment twice.
    # The real runtime decisions determine the actual printed count.
    for decision in decisions:
        if decision["covered"]:
            covered_count += 1

    # Covered=True means omit that source line from the filtered copy.
    # Uncovered and unprocessed source lines are copied without alteration.
    write_filtered_word_rules(decisions, generated_path, filtered_path)

    # Print the counts and the new file path; the original file was not rewritten.
    print(f"Start/middle/end rules read: {len(rules):,}")
    print(f"Whole-word rules read: {len(whole_word_rules):,}")
    print(f"Whole-word rules with identical start/middle/end coverage: {covered_count:,}")
    print(f"Filtered file: {filtered_path}")
    # The direct-execution block passes this success value to SystemExit.
    return 0


def read_current_rules(pattern_paths):
    """Turn parsed rule definitions into the combined start/middle/end rule list.

    Example definition from _read_definitions(path):
        {"options": "BCTk-1*", "trigger": "inetr", "replacement": "inter", ...}
    The * selects kind="start". A copy gains kind and order:
        {"options": "BCTk-1*", "trigger": "inetr", "replacement": "inter",
         "kind": "start", "order": the accepted-rule sequence number, ...}
    For BCTk-1?, the kind is "end". For BCTk-1?*, the kind is "middle";
    its complete trigger can be replaced anywhere in the whole-word rule.

    The returned rules list combines accepted dictionaries across the explicitly
    supplied files, in that order. Other AutoHotkey flags remain stored as text;
    this reader does not interpret their runtime behavior.
    """
    # The combined selected-rule container starts as rules = [].
    rules = []
    # Visit each supplied file in order, using a per-file definitions list.
    for path in pattern_paths:
        # Example definition: {"options": "BCTk-1*", "trigger": "inetr",
        # "replacement": "inter", ...}. It has no kind/order fields yet.
        for definition in _read_definitions(path):
            # options is "BCTk-1*", distinct from the trigger text "inetr".
            options = definition["options"]

            # Disabled positional flags leave this definition outside the simple reader.
            if "*0" in options or "?0" in options:
                continue
            # "BCTk-1*" selects kind="start".
            if "*" in options and "?" not in options:
                kind = "start"
            # "BCTk-1?" selects kind="end".
            elif "?" in options and "*" not in options:
                kind = "end"
            # "BCTk-1?*" selects kind="middle": the trigger can occur anywhere.
            elif "*" in options and "?" in options:
                kind = "middle"
            # "" (an individual whole-word rule) does not select a pattern kind.
            else:
                continue

            # Make a separate dictionary before adding classification fields.
            # Adding kind/order to rule does not alter the original definition.
            rule = definition.copy()
            # The inetr rule gains "kind": "start"; the atde rule gains "kind": "end".
            rule["kind"] = kind
            # With two accepted rules already stored, the next gets order=2.
            # This counts accepted rules across files, not file line numbers.
            rule["order"] = len(rules)
            # Append the extended dictionary; several rules may share a trigger.
            rules.append(rule)
    # main() passes this combined list to the direct start/middle/end checker.
    return rules


def read_generated_word_rules(generated_path):
    """Return a list containing individual typo/correction dictionaries.

    For ::inetrnet::internet, _read_definitions(generated_path) supplies:
        {"options": "", "trigger": "inetrnet", "replacement": "internet", ...}
    The empty options string passes the filter. The SAME dictionary is appended
    to whole_word_rules, not a copy. Later, for whole_word_rule in whole_word_rules assigns that dictionary
    to whole_word_rule, so whole_word_rule["trigger"] supplies "inetrnet" to the coverage checker.
    """
    # The selected whole-word rule collection starts as whole_word_rules = [].
    whole_word_rules = []
    # The generated example supplies {"options": "", "trigger": "inetrnet",
    # "replacement": "internet", ...}.
    for definition in _read_definitions(generated_path):
        # The empty options string passes; definitions containing flags do not.
        if definition["options"] == "":
            # Append the SAME dictionary, with no definition.copy() or field changes.
            whole_word_rules.append(definition)
    # main() receives the list; later, for whole_word_rule in whole_word_rules retrieves these
    # same dictionaries and reads their trigger/replacement fields.
    return whole_word_rules

def write_filtered_word_rules(decisions, generated_path, output_path):
    """Copy original lines except those marked covered into a new AHK file.

    For example, if a decision for ::inetrnet::internet has covered=True,
    that whole-word rule's source line number is omitted. A covered=False decision keeps
    its line. Comments, blank lines and skipped/unprocessed lines are also kept.

    Original UTF-8 bytes, BOM state and each retained line ending are preserved.
    The output must be a different, new file: an existing file is not overwritten.
    """
    source = Path(generated_path)
    target = Path(output_path)
    if source.resolve() == target.resolve():
        raise ValueError("The filtered output must not replace the original.")

    # Read the original once. Split exactly as the reader did so stored source
    # line numbers refer to the same lines, including any blank/comment lines.
    original_bytes = source.read_bytes()
    original_lines = original_bytes.decode("utf-8-sig").splitlines(keepends=True)
    covered_lines = set()
    for decision in decisions:
        whole_word_rule = decision["whole_word_rule"]
        line_idx = whole_word_rule["line"] - 1
        if line_idx < 0 or line_idx >= len(original_lines):
            raise ValueError("The source changed after its whole-word rules were read.")
        if original_lines[line_idx].encode("utf-8") != whole_word_rule["raw_line"]:
            raise ValueError("The source changed after its whole-word rules were read.")
        if decision["covered"]:
            covered_lines.add(whole_word_rule["line"])

    # Preserve a file-level BOM even when its first hotstring is filtered out.
    filtered_bytes = bytearray()
    if original_bytes.startswith(b"\xef\xbb\xbf"):
        filtered_bytes.extend(b"\xef\xbb\xbf")

    # Example: covered_lines={4145} omits only that numbered source line.
    # All other lines retain their exact text, spacing and individual newline.
    for line_idx, raw_line in enumerate(original_lines, start=1):
        if line_idx not in covered_lines:
            filtered_bytes.extend(raw_line.encode("utf-8"))

    if source.read_bytes() != original_bytes:
        raise ValueError("The source changed while preparing the filtered copy.")
    # Exclusive creation prevents accidentally replacing an earlier output.
    with target.open("xb") as output:
        output.write(filtered_bytes)
    if target.read_bytes() != filtered_bytes:
        raise RuntimeError("Filtered output byte verification failed.")


# Direct execution calls main(); importing leaves the containers unbuilt.
if __name__ == "__main__":
    raise SystemExit(main())
