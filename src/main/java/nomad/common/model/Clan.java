package nomad.common.model;

import java.time.OffsetDateTime;

public class Clan {
	private long id;

	private String name;

	private long leaderCharaId;

	private String comment;

	private String notice;

	private OffsetDateTime noticeTime;

	private long noticeCharaId;

	private byte[] currentEmblem;

	private byte[] draftEmblem;

	public long getId() {
		return id;
	}

	public void setId(long id) {
		this.id = id;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public long getLeaderCharaId() {
		return leaderCharaId;
	}

	public void setLeaderCharaId(long leaderCharaId) {
		this.leaderCharaId = leaderCharaId;
	}

	public String getComment() {
		return comment;
	}

	public void setComment(String comment) {
		this.comment = comment;
	}

	public String getNotice() {
		return notice;
	}

	public void setNotice(String notice) {
		this.notice = notice;
	}

	public OffsetDateTime getNoticeTime() {
		return noticeTime;
	}

	public void setNoticeTime(OffsetDateTime noticeTime) {
		this.noticeTime = noticeTime;
	}

	public long getNoticeCharaId() {
		return noticeCharaId;
	}

	public void setNoticeCharaId(long noticeCharaId) {
		this.noticeCharaId = noticeCharaId;
	}

	public byte[] getCurrentEmblem() {
		return currentEmblem;
	}

	public void setCurrentEmblem(byte[] currentEmblem) {
		this.currentEmblem = currentEmblem;
	}

	public byte[] getDraftEmblem() {
		return draftEmblem;
	}

	public void setDraftEmblem(byte[] draftEmblem) {
		this.draftEmblem = draftEmblem;
	}

	@Override
	public String toString() {
		return "Clan{" +
			"id=" + id +
			", name='" + name + '\'' +
			", leaderCharaId=" + leaderCharaId +
			", comment='" + comment + '\'' +
			", notice='" + notice + '\'' +
			", noticeTime=" + noticeTime +
			", noticeCharaId=" + noticeCharaId +
			'}';
	}
}
