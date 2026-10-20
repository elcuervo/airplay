module Airplay
  module Queue
    # Public: Command and parameter names that differ between firmware profiles.
    module Command
      DEFAULT_COMMANDS = {
        insert: "insertPlayQueueItem",
        remove: "removePlayQueueItem",
        select: "selectQueueItem",
        seek: "seekToTime",
        snapshot: "getPlaybackState",
        rate: "setRate",
        property: "setProperty"
      }.freeze

      DEFAULT_FIELDS = {
        uuid: "uuid",
        url: "url",
        media_kind: "mediaType",
        secure: "secure",
        start_position: "startPosition",
        seek_position: "position",
        rate: "rate",
        property_name: "name",
        property_value: "value",
        request_id: "requestID"
      }.freeze
    end
  end
end
