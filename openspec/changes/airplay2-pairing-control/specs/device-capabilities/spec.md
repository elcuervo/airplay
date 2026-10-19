# Spec Delta

## ADDED Requirements

### Requirement: Authoritative Info overrides discovered capabilities

After `GET /info` succeeds on a paired connection, the sender SHALL replace the discovered value of every capability key the response carries with the response's value, and SHALL keep the discovered value for keys the response does not carry.

#### Scenario: A wire-reported capability corrects the discovered model

- **WHEN** the TXT-derived model reports that a device lacks the video v2 capability and the `GET /info` response reports it present
- **THEN** the capability model reports video v2 present for the rest of the session

#### Scenario: Keys absent from the response keep their discovered value

- **WHEN** the `GET /info` response omits a capability key present in the TXT-derived model
- **THEN** that key keeps the value taken from the TXT record

### Requirement: Authoritative Info reconciliation is observable

The capability model SHALL record, for every reconciled key, whether its value came from discovery or from the authoritative `GET /info` response, and SHALL make any key where the two disagreed available for inspection.

#### Scenario: Provenance is reported per key

- **WHEN** a device whose response confirms some keys and contradicts others is reconciled
- **THEN** each affected key reports the source of its current value and the contradicting keys are listed as disagreements

#### Scenario: A reconciliation without disagreement still records its source

- **WHEN** the response agrees with every discovered key it carries
- **THEN** those keys report the authoritative response as their source and the disagreement list is empty
